set define off

-- Foundation-data cache.
--
-- Populated two ways, and every row records which:
--   ENDPOINT:  read straight from a foundation service that returns rows
--   DERIVED:   harvested from the item or order feed
--
-- The derived route is not a shortcut. The foundation services are publish
-- queues, and which of them hold anything depends on the tenant and the week.
-- On STG in 2026-09, diffid, diffgroup, uda, supplier, store and warehouse
-- publish; merchhier/* still answers HTTP 200 with zero rows. The item feed
-- carries the hierarchy, differentiator and supplier values regardless, so the
-- hierarchy is recovered from there.
--
-- Every feed that publishes also pages, and fetch_all follows the pages. Reading
-- only the first one was harmless while the feeds were empty and silently
-- truncated them once they filled: diffid stopped at exactly 500.

prompt Creating master_pkg

create or replace package master_pkg authid definer as
    -- Refreshes MASTER_DATA so the console can offer dropdowns
    -- without a round trip per keystroke. Failures are recorded per source
    -- rather than aborting the run.
    procedure refresh_all(o_summary out clob);

end master_pkg;
/

show errors

create or replace package body master_pkg as

    -- p_keep_existing = 'Y' inserts a missing row and leaves an existing one
    -- untouched. The item harvest uses it for the hierarchy, which is loaded
    -- authoritatively from an RDS extract (deploy/mdutils/load_rds_hierarchy.sql);
    -- a plain upsert would relabel those rows DERIVED on every refresh.
    procedure upsert(
        p_type   in varchar2,
        p_code   in varchar2,
        p_parent in varchar2,
        p_desc   in varchar2,
        p_attrs  in clob,
        p_source in varchar2,
        p_keep_existing in varchar2 default 'N'
    ) is
    begin
        if p_code is null then
            return;
        end if;
        merge into master_data d
        using (select p_type dt, p_code dc, nvl(p_parent, '~') pc from dual) s
        on (d.data_type = s.dt and d.data_code = s.dc and d.parent_code = s.pc)
        when matched then update set
            d.description = nvl(p_desc, d.description),
            d.attributes = nvl(p_attrs, d.attributes),
            d.source = p_source,
            d.refreshed_at = systimestamp
            where p_keep_existing = 'N'
        when not matched then insert (data_type, data_code, parent_code, description, attributes, source)
        values (s.dt, s.dc, s.pc, p_desc, p_attrs, p_source);
    end;

    procedure log_refresh(
        p_type in varchar2,
        p_source in varchar2,
        p_status in number,
        p_rows in number,
        p_message in varchar2,
        p_started in timestamp with time zone
    ) is
    begin
        merge into master_refresh r
        using (select p_type dt from dual) s
        on (r.data_type = s.dt)
        when matched then update set
            r.source = p_source, r.http_status = p_status, r.row_count = p_rows,
            r.message = p_message, r.started_at = p_started, r.completed_at = systimestamp
        when not matched then insert (data_type, source, http_status, row_count, message, started_at, completed_at)
        values (p_type, p_source, p_status, p_rows, p_message, p_started, systimestamp);
    end;

    -- Every row a foundation feed holds, across all its pages.
    --
    -- The envelope is {items, hasMore, links[]}, and the next page is named by an
    -- offsetkey inside the rel=next link, the same key the item harvest pages on.
    -- A few services (codes, banners, channels) answer a bare array instead of the
    -- envelope; that is a single page by construction, and it is why banners and
    -- channels used to fail ORA-40587 on json_object_t.parse.
    --
    -- o_status is the last page's HTTP status. A failure after page one returns
    -- what was read so far with that status, and the caller decides whether a
    -- partial read is worth keeping. o_truncated is true when p_max_pages ran out
    -- with the feed still saying hasMore, so a cap reads as a cap in the refresh
    -- log rather than as the size of the tenant's data.
    function fetch_all(
        p_path      in varchar2,
        p_limit     in number,
        o_status    out number,
        o_truncated out boolean,
        p_max_pages in number default 200
    ) return json_array_t is
        l_all json_array_t := json_array_t();
        l_body clob;
        l_root json_object_t;
        l_items json_array_t;
        l_links json_array_t;
        l_link json_object_t;
        l_offset varchar2(400);
        l_page number := 0;
        l_path varchar2(1000);
    begin
        o_truncated := false;
        loop
            l_page := l_page + 1;
            l_path := p_path || '?limit=' || p_limit;
            if l_offset is not null then
                l_path := l_path || '&offsetkey=' || l_offset;
            end if;

            l_body := client_pkg.get_json(l_path, o_status);
            exit when o_status not between 200 and 299;

            begin
                l_items := json_array_t.parse(l_body);
                l_root := null;
            exception
                when others then
                    l_root := json_object_t.parse(l_body);
                    l_items := l_root.get_array('items');
            end;

            if l_items is not null then
                for i in 0 .. l_items.get_size - 1 loop
                    l_all.append(l_items.get(i));
                end loop;
            end if;

            l_offset := null;
            if l_root is not null and nvl(l_root.get_string('hasMore'), 'false') = 'true' then
                l_links := l_root.get_array('links');
                if l_links is not null then
                    for i in 0 .. l_links.get_size - 1 loop
                        l_link := treat(l_links.get(i) as json_object_t);
                        if l_link.get_string('rel') = 'next' then
                            l_offset := regexp_substr(l_link.get_string('href'), '[?&]offsetkey=([^&]+)', 1, 1, null, 1);
                        end if;
                    end loop;
                end if;
            end if;

            exit when l_offset is null;
            if l_page >= p_max_pages then
                o_truncated := true;
                exit;
            end if;
        end loop;
        return l_all;
    end;

    procedure load_direct(
        p_type       in varchar2,
        p_path       in varchar2,
        p_code_field in varchar2,
        p_desc_field in varchar2,
        p_limit      in number default 500
    ) is
        l_status number;
        l_truncated boolean;
        l_items json_array_t;
        l_row json_object_t;
        l_count number := 0;
        l_started timestamp with time zone := systimestamp;
        l_source varchar2(200) := 'ENDPOINT:' || p_path;
    begin
        l_items := fetch_all(p_path, p_limit, l_status, l_truncated);
        if l_status not between 200 and 299 and l_items.get_size = 0 then
            log_refresh(p_type, l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        for i in 0 .. l_items.get_size - 1 loop
            l_row := treat(l_items.get(i) as json_object_t);
            upsert(
                p_type => p_type,
                p_code => l_row.get_string(p_code_field),
                p_parent => null,
                p_desc => l_row.get_string(p_desc_field),
                p_attrs => l_row.to_clob,
                p_source => l_source
            );
            l_count := l_count + 1;
        end loop;

        log_refresh(p_type, l_source, l_status, l_count,
            case when l_count = 0 then 'Service returned no rows (empty publish queue).'
                 when l_truncated then 'Stopped at the page cap; the feed has more.'
                 when l_status not between 200 and 299 then 'Partial: a later page answered HTTP ' || l_status || '.'
            end,
            l_started);
    exception
        when others then
            log_refresh(p_type, l_source, l_status, l_count, substr(sqlerrm, 1, 1000), l_started);
    end;

    -- UDAs need more than a code and a description, so they do not go through
    -- load_direct.
    --
    -- Two things depend on this. item/uda/create rejects a row without displayType,
    -- and displayType decides which of udaValue / udaText / udaDate carries the
    -- value - so the mapper has to know a UDA's type before it can send it.
    -- Validation then needs the list of values, to reject a code the tenant will not
    -- accept before a request burns an item number finding out.
    --
    -- Definitions land as UDA; their list-of-values rows land as UDA_VALUE keyed by
    -- parent_code = the udaId, which is what makes the lookup a primary key hit.
    procedure load_udas(p_limit in number default 100) is
        l_status number;
        l_truncated boolean;
        l_items json_array_t;
        l_row json_object_t;
        l_values json_array_t;
        l_value json_object_t;
        l_uda_id varchar2(120);
        l_count number := 0;
        l_values_count number := 0;
        l_started timestamp with time zone := systimestamp;
        l_path varchar2(200) := '/MerchIntegrations/services/foundation/uda';
        l_source varchar2(200) := 'ENDPOINT:' || l_path;
    begin
        -- A smaller page than the other feeds: each UDA row carries its whole
        -- value list, and Style (66040) alone is ~2MB of values on UAT.
        l_items := fetch_all(l_path, p_limit, l_status, l_truncated);
        if l_status not between 200 and 299 and l_items.get_size = 0 then
            log_refresh('UDA', l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        for i in 0 .. l_items.get_size - 1 loop
            l_row := treat(l_items.get(i) as json_object_t);
            l_uda_id := to_char(l_row.get_number('udaId'));

            upsert(
                p_type   => 'UDA',
                p_code   => l_uda_id,
                p_parent => null,
                -- udaDescription, not udaDesc. The earlier load_direct call asked for
                -- the wrong name and stored a null description for every row.
                p_desc   => l_row.get_string('udaDescription'),
                p_attrs  => l_row.to_clob,
                p_source => l_source
            );
            l_count := l_count + 1;

            -- FF and DT UDAs carry "udaListOfValues": null rather than omitting the
            -- key, so has() is true and get_array returns a null object. Calling
            -- get_size on that is ORA-30625, which aborted the whole load at the
            -- first free-form UDA and left every value after it unloaded.
            l_values := null;
            if l_row.has('udaListOfValues') and l_row.get('udaListOfValues').is_array then
                l_values := l_row.get_array('udaListOfValues');
            end if;
            if l_values is not null then
                for j in 0 .. l_values.get_size - 1 loop
                    l_value := treat(l_values.get(j) as json_object_t);
                    upsert(
                        p_type   => 'UDA_VALUE',
                        p_code   => to_char(l_value.get_number('udaValue')),
                        p_parent => l_uda_id,
                        p_desc   => l_value.get_string('udaValueDescription'),
                        p_attrs  => l_value.to_clob,
                        p_source => l_source
                    );
                    l_values_count := l_values_count + 1;
                end loop;
            end if;
        end loop;

        log_refresh('UDA', l_source, l_status, l_count,
            case when l_count = 0
                 then 'Service returned no rows (empty publish queue).'
                 else 'Loaded ' || l_values_count || ' list-of-values rows as UDA_VALUE.'
                      || case when l_truncated then ' Stopped at the page cap; the feed has more.' end
            end,
            l_started);
    exception
        when others then
            log_refresh('UDA', l_source, l_status, l_count, substr(sqlerrm, 1, 1000), l_started);
    end;

    -- Differentiators land as DIFF_<diffType> - DIFF_C, DIFF_S, DIFF_HL and so on -
    -- which is what the item harvest writes too, so validation and the console's
    -- lists see one set whichever route a value arrived by. They used to land as
    -- DIFF_SVC, a type nothing read.
    --
    -- The type set is the tenant's, not ours. STG gained HL (High Level Colour)
    -- and LL (Low Level Colour) in 2026-09 and labelled SC "Supplier Colour - to be
    -- deleted"; loading by the row's own type is what keeps that visible here.
    procedure load_diffs(p_limit in number default 500) is
        l_status number;
        l_truncated boolean;
        l_items json_array_t;
        l_row json_object_t;
        l_count number := 0;
        l_started timestamp with time zone := systimestamp;
        l_path varchar2(200) := '/MerchIntegrations/services/foundation/diffid';
        l_source varchar2(200) := 'ENDPOINT:' || l_path;
    begin
        l_items := fetch_all(l_path, p_limit, l_status, l_truncated);
        if l_status not between 200 and 299 and l_items.get_size = 0 then
            log_refresh('DIFF', l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        for i in 0 .. l_items.get_size - 1 loop
            l_row := treat(l_items.get(i) as json_object_t);
            upsert(
                p_type   => 'DIFF_' || nvl(l_row.get_string('diffType'), 'X'),
                p_code   => l_row.get_string('diffId'),
                p_parent => null,
                p_desc   => l_row.get_string('diffDescription'),
                p_attrs  => l_row.to_clob,
                p_source => l_source
            );
            l_count := l_count + 1;
        end loop;

        log_refresh('DIFF', l_source, l_status, l_count,
            case when l_count = 0 then 'Service returned no rows (empty publish queue).'
                 when l_truncated then 'Stopped at the page cap; the feed has more.'
            end,
            l_started);
    exception
        when others then
            log_refresh('DIFF', l_source, l_status, l_count, substr(sqlerrm, 1, 1000), l_started);
    end;

    -- A differentiator group says which diffs are legal children of a parent that
    -- carries it: MFCS rejects a child whose colour is outside the parent's group.
    -- Groups land as DIFF_GROUP (attributes carry diffType); members land as
    -- DIFF_GROUP_MEMBER with parent_code = the group, so "is this size in that
    -- group" is a primary key hit.
    --
    -- Members are replaced per group rather than merged. The group's row in the
    -- feed is the whole membership, and a merge would keep a diff the tenant has
    -- since removed from the group - which validation would then wrongly accept.
    procedure load_diff_groups(p_limit in number default 100) is
        l_status number;
        l_truncated boolean;
        l_items json_array_t;
        l_row json_object_t;
        l_details json_array_t;
        l_detail json_object_t;
        l_group varchar2(120);
        l_count number := 0;
        l_members number := 0;
        l_started timestamp with time zone := systimestamp;
        l_path varchar2(200) := '/MerchIntegrations/services/foundation/diffgroup';
        l_source varchar2(200) := 'ENDPOINT:' || l_path;
    begin
        l_items := fetch_all(l_path, p_limit, l_status, l_truncated);
        if l_status not between 200 and 299 and l_items.get_size = 0 then
            log_refresh('DIFF_GROUP', l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        for i in 0 .. l_items.get_size - 1 loop
            l_row := treat(l_items.get(i) as json_object_t);
            l_group := l_row.get_string('diffGroupId');
            continue when l_group is null;

            l_details := null;
            if l_row.has('details') and l_row.get('details').is_array then
                l_details := l_row.get_array('details');
            end if;

            -- The group row without its member list; the members are rows of
            -- their own, and repeating them here would store every group twice.
            l_row.remove('details');
            upsert('DIFF_GROUP', l_group, null, l_row.get_string('diffGroupDescription'),
                   l_row.to_clob, l_source);
            l_count := l_count + 1;

            delete from master_data
             where data_type = 'DIFF_GROUP_MEMBER'
               and parent_code = l_group;

            if l_details is not null then
                for j in 0 .. l_details.get_size - 1 loop
                    l_detail := treat(l_details.get(j) as json_object_t);
                    upsert('DIFF_GROUP_MEMBER', l_detail.get_string('diffId'), l_group,
                           null, l_detail.to_clob, l_source);
                    l_members := l_members + 1;
                end loop;
            end if;
        end loop;

        log_refresh('DIFF_GROUP', l_source, l_status, l_count,
            case when l_count = 0 then 'Service returned no rows (empty publish queue).'
                 else 'Loaded ' || l_members || ' member rows as DIFF_GROUP_MEMBER.'
                      || case when l_truncated then ' Stopped at the page cap; the feed has more.' end
            end,
            l_started);
    exception
        when others then
            log_refresh('DIFF_GROUP', l_source, l_status, l_count, substr(sqlerrm, 1, 1000), l_started);
    end;

    procedure harvest_from_items(p_pages in number default 10, p_limit in number default 200) is
        l_status number;
        l_body clob;
        l_root json_object_t;
        l_items json_array_t;
        l_it json_object_t;
        l_sups json_array_t;
        l_sup json_object_t;
        l_started timestamp with time zone := systimestamp;
        l_source varchar2(200) := 'DERIVED:/services/foundation/item';
        l_path varchar2(400);
        l_offset varchar2(200);
        l_items_seen number := 0;
        l_more boolean := true;
        l_page number := 0;
        l_dept varchar2(120);
        l_class varchar2(120);
    begin
        while l_more and l_page < p_pages loop
            l_page := l_page + 1;
            l_path := '/MerchIntegrations/services/foundation/item?limit=' || p_limit;
            if l_offset is not null then
                l_path := l_path || '&offsetkey=' || l_offset;
            end if;

            l_body := client_pkg.get_json(l_path, l_status);
            exit when l_status not between 200 and 299;

            l_root := json_object_t.parse(l_body);
            l_items := l_root.get_array('items');
            exit when l_items is null or l_items.get_size = 0;

            for i in 0 .. l_items.get_size - 1 loop
                l_it := treat(l_items.get(i) as json_object_t);
                l_items_seen := l_items_seen + 1;
                l_offset := l_it.get_string('item');

                l_dept := to_char(l_it.get_number('dept'));
                l_class := to_char(l_it.get_number('class'));

                -- Insert-only: the RDS extract is the authority for the hierarchy,
                -- and the harvest only fills in a code it has not supplied.
                upsert('DEPARTMENT', l_dept, null, l_it.get_string('deptName'), null, l_source, 'Y');
                upsert('CLASS', l_class, l_dept, l_it.get_string('className'), null, l_source, 'Y');
                upsert('SUBCLASS', to_char(l_it.get_number('subclass')),
                       l_dept || '.' || l_class, l_it.get_string('subclassName'), null, l_source, 'Y');

                -- diff1/diff2 carry their own type flag (C = colour, S = size).
                if l_it.get_string('diff1') is not null then
                    upsert('DIFF_' || nvl(l_it.get_string('diff1Type'), 'X'),
                           l_it.get_string('diff1'), null, null, null, l_source);
                end if;
                if l_it.get_string('diff2') is not null then
                    upsert('DIFF_' || nvl(l_it.get_string('diff2Type'), 'X'),
                           l_it.get_string('diff2'), null, null, null, l_source);
                end if;

                if l_it.get_string('standardUom') is not null then
                    upsert('UOM', l_it.get_string('standardUom'), null, null, null, l_source);
                end if;

                begin
                    l_sups := l_it.get_array('supplier');
                    if l_sups is not null then
                        for j in 0 .. l_sups.get_size - 1 loop
                            l_sup := treat(l_sups.get(j) as json_object_t);
                            upsert('SUPPLIER', to_char(l_sup.get_number('supplier')), null,
                                   l_sup.get_string('supplierName'), l_sup.to_clob, l_source);
                        end loop;
                    end if;
                exception when others then null;
                end;
            end loop;

            l_more := nvl(l_root.get_string('hasMore'), 'false') = 'true';
        end loop;

        log_refresh('DERIVED_FROM_ITEMS', l_source, l_status, l_items_seen,
            'Scanned ' || l_items_seen || ' items across ' || l_page || ' page(s).', l_started);
    exception
        when others then
            log_refresh('DERIVED_FROM_ITEMS', l_source, l_status, l_items_seen, substr(sqlerrm, 1, 1000), l_started);
    end;

    procedure harvest_from_orders(p_limit in number default 200) is
        l_status number;
        l_body clob;
        l_items json_array_t;
        l_o json_object_t;
        l_started timestamp with time zone := systimestamp;
        l_source varchar2(200) := 'DERIVED:/services/procurement/order';
        l_seen number := 0;
    begin
        l_body := client_pkg.get_json('/MerchIntegrations/services/procurement/order?limit=' || p_limit, l_status);
        if l_status not between 200 and 299 then
            log_refresh('DERIVED_FROM_ORDERS', l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        l_items := json_object_t.parse(l_body).get_array('items');
        for i in 0 .. l_items.get_size - 1 loop
            l_o := treat(l_items.get(i) as json_object_t);
            l_seen := l_seen + 1;
            upsert('SUPPLIER', to_char(l_o.get_number('supplier')), null, null, null, l_source);
            upsert('CURRENCY', l_o.get_string('currencyCode'), null, null, null, l_source);
            if l_o.get_number('virtualWarehouse') is not null then
                upsert('LOCATION_W', to_char(l_o.get_number('virtualWarehouse')), null,
                       'Virtual warehouse', null, l_source);
            end if;
            if l_o.get_number('physicalLocation') is not null then
                upsert('LOCATION_P', to_char(l_o.get_number('physicalLocation')), null,
                       'Physical location', null, l_source);
            end if;
            if l_o.get_string('terms') is not null then
                upsert('TERMS', l_o.get_string('terms'), null, l_o.get_string('termsCode'), null, l_source);
            end if;
        end loop;

        log_refresh('DERIVED_FROM_ORDERS', l_source, l_status, l_seen,
            'Scanned ' || l_seen || ' orders.', l_started);
    exception
        when others then
            log_refresh('DERIVED_FROM_ORDERS', l_source, l_status, l_seen, substr(sqlerrm, 1, 1000), l_started);
    end;

    -- administration/operations/codes returns the RMS code_detail table: ~797 code
    -- types, each with its own values. Unlike the other foundation services this one
    -- actually has data, so it is the authoritative source for fixed-value dropdowns
    -- that would otherwise be hardcoded in CONFIG or inferred from items.
    --
    -- Stored as data_type CODE_<codeType>, with the code type as parent_code so the
    -- console can group them.
    procedure load_code_details(p_limit in number default 5000) is
        l_status number;
        l_body clob;
        l_types json_array_t;
        l_type json_object_t;
        l_details json_array_t;
        l_detail json_object_t;
        l_started timestamp with time zone := systimestamp;
        l_source varchar2(200) := 'ENDPOINT:/services/administration/operations/codes';
        l_count number := 0;
        l_code_type varchar2(40);
    begin
        l_body := client_pkg.get_json(
            '/MerchIntegrations/services/administration/operations/codes?limit=' || p_limit, l_status);
        if l_status not between 200 and 299 then
            log_refresh('CODE_DETAIL', l_source, l_status, 0, 'HTTP ' || l_status, l_started);
            return;
        end if;

        -- This service answers with a bare array, not the usual {items:[...]} envelope.
        begin
            l_types := json_array_t.parse(l_body);
        exception
            when others then
                l_types := json_object_t.parse(l_body).get_array('items');
        end;

        for i in 0 .. l_types.get_size - 1 loop
            l_type := treat(l_types.get(i) as json_object_t);
            l_code_type := l_type.get_string('codeType');

            -- The code type itself, so a caller can list what exists.
            upsert('CODE_TYPE', l_code_type, null, l_type.get_string('description'), null, l_source);

            l_details := l_type.get_array('details');
            if l_details is not null then
                for j in 0 .. l_details.get_size - 1 loop
                    l_detail := treat(l_details.get(j) as json_object_t);
                    upsert(
                        p_type => 'CODE_' || l_code_type,
                        p_code => l_detail.get_string('code'),
                        p_parent => l_code_type,
                        p_desc => l_detail.get_string('codeDescription'),
                        p_attrs => l_detail.to_clob,
                        p_source => l_source);
                    l_count := l_count + 1;
                end loop;
            end if;
        end loop;

        log_refresh('CODE_DETAIL', l_source, l_status, l_count,
            'Loaded ' || l_count || ' value(s) across ' || l_types.get_size || ' code type(s).',
            l_started);
    exception
        when others then
            log_refresh('CODE_DETAIL', l_source, l_status, l_count, substr(sqlerrm, 1, 1000), l_started);
    end;

    procedure refresh_all(o_summary out clob) is
        l_root json_object_t := json_object_t();
        l_arr json_array_t := json_array_t();
        l_row json_object_t;
    begin
        -- Services that return rows on this tenant.
        load_direct('BRAND', '/MerchIntegrations/services/item/brands', 'brandName', 'brandDescription');
        load_direct('SEASON', '/MerchIntegrations/services/item/foundation/seasons', 'season', 'description');
        load_direct('ORG_HIER', '/MerchIntegrations/services/foundation/orghier', 'hierarchyId', 'hierarchyName');
        load_direct('BANNER', '/MerchIntegrations/services/foundation/banners', 'bannerId', 'bannerName');
        load_direct('CHANNEL', '/MerchIntegrations/services/foundation/channels', 'channelId', 'channelName');
        load_code_details;
        load_udas;

        -- Attempted anyway, so the refresh log records that it is still empty
        -- rather than leaving it a mystery.
        load_direct('DEPARTMENT_SVC', '/MerchIntegrations/services/foundation/merchhier/deps', 'dept', 'deptName');
        load_direct('SUPPLIER_SVC', '/MerchIntegrations/services/foundation/supplier', 'supplier', 'supplierName');
        -- warehouse / warehouseName, not wh / whName. Asking for the wrong names
        -- loaded nothing at all, silently, for as long as this call has existed -
        -- the same failure the UDA loader had with udaDesc. The row also carries
        -- physicalWarehouse and primaryVirtualWarehouse, which is where the
        -- physical-to-virtual translation comes from.
        load_direct('WAREHOUSE_SVC', '/MerchIntegrations/services/foundation/warehouse', 'warehouse', 'warehouseName');
        load_direct('STORE_SVC', '/MerchIntegrations/services/foundation/store', 'store', 'storeName');

        harvest_from_items;
        harvest_from_orders;

        -- After the harvest, not before. The harvest writes the same DIFF_* rows
        -- from the item feed and stamps them DERIVED; loading the diff service
        -- last leaves every diff the service publishes recorded as ENDPOINT, with
        -- the service's description, and DERIVED marking only what it does not.
        load_diffs;
        load_diff_groups;
        commit;

        for r in (
            select m.data_type, count(*) cnt, max(m.source) src,
                   to_char(max(m.refreshed_at), 'YYYY-MM-DD"T"HH24:MI:SS') last_refresh
              from master_data m
             group by m.data_type
             order by m.data_type
        ) loop
            l_row := json_object_t();
            l_row.put('dataType', r.data_type);
            l_row.put('count', r.cnt);
            l_row.put('source', r.src);
            l_row.put('refreshedAt', r.last_refresh);
            l_arr.append(l_row);
        end loop;
        l_root.put('cached', l_arr);

        l_arr := json_array_t();
        for r in (
            select data_type, source, http_status, row_count, message,
                   to_char(completed_at, 'YYYY-MM-DD"T"HH24:MI:SS') completed
              from master_refresh order by data_type
        ) loop
            l_row := json_object_t();
            l_row.put('dataType', r.data_type);
            l_row.put('source', r.source);
            l_row.put('httpStatus', r.http_status);
            l_row.put('rowCount', r.row_count);
            l_row.put('message', r.message);
            l_row.put('completedAt', r.completed);
            l_arr.append(l_row);
        end loop;
        l_root.put('log', l_arr);

        o_summary := l_root.to_clob;
    end;
end master_pkg;
/

show errors
