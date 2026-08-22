set define off

-- Reconciles the SKUs a request needs against the SKUs a style actually has.
--
-- Why this exists: PLM does not know about SKUs. It sends MODIFY_STYLE or an
-- order operation naming a style and a colour, and expects the integration to
-- work out the rest.
--
-- And a colour change cannot be applied to an existing SKU. In the RMS model a
-- diff combination *defines* the item, so a new colour means new children. This
-- was confirmed against the tenant: PUT items/update with a changed diff1
-- returned HTTP 200 SUCCESS and left the item untouched. MFCS does not reject
-- the change, it silently ignores it - so an integration that simply forwards a
-- colour change reports success while nothing happens.
--
-- Everything here is read-only analysis. Creating the missing children is the
-- orchestrator's job; this package tells it what is missing.

prompt Creating sku_pkg

create or replace package sku_pkg authid definer as

    -- Children of a style, read through RmsReSTServices Item/itemDetail, which
    -- returns a style together with its children in one call.
    -- Returns {"skus":[{"item","diff1","diff2","status"}], "available":true|false}
    function existing_skus(p_style in varchar2) return clob;

    -- Compares the colour and size curve a request needs against what the style
    -- already has, and reports which SKUs exist and which would have to be
    -- created before the request can proceed.
    --
    -- p_sizes is a colon-separated list of display sizes, e.g. '7:8:9'. They are
    -- mapped to MFCS size diffs through MAP.SIZE.* the same way the payload
    -- mapper does, so this and the outbound payload cannot disagree.
    function resolve_gap(
        p_style  in varchar2,
        p_colour in varchar2,
        p_sizes  in varchar2
    ) return clob;

    -- The attributes a new child has to inherit from the style it joins.
    --
    -- A child must sit in its parent's merchandise hierarchy, and the document that
    -- arrives with an order does not carry one: PLM names a style and expects the
    -- integration to know the rest. The same read supplies the supplier, cost and
    -- origin country to fall back on when the document does not name them, which
    -- matters because MFCS will not approve an item that has no sourcing.
    --
    -- This reads itemDetail, not foundation/item, and the difference is not a
    -- preference. foundation/item is fed by the publish queue: it answered 404 for a
    -- style that had just been created and approved, while itemDetail returned it in
    -- full. Anything that has to work on a style this integration created moments
    -- ago cannot be built on the feed.
    --
    -- itemDetail is a third vocabulary, after the item feed's and the write
    -- services'. It says classAttribute for class, itemDesc/shortDesc for the
    -- descriptions, primarySuppInd for primarySupplierInd and originCountryId for
    -- originCountry. Translating is this function's job, so callers see one set of
    -- names. It carries no costZoneGroupId, standardUom or storeOrderMultiple; those
    -- keys come back absent and the payload builders fall back to configuration.
    --
    -- Returns {"available":true|false, "dept","class","subclass","status",
    -- "originalRetail","itemDescription","shortDescription","supplier","unitCost",
    -- "originCountry"}.
    function style_attributes(p_style in varchar2) return clob;
end sku_pkg;
/

show errors

create or replace package body sku_pkg as

    function size_diff(p_display in varchar2) return varchar2 is
    begin
        return config_pkg.get_config('MAP.SIZE.' || p_display);
    end;

    function colour_diff(p_colour in varchar2) return varchar2 is
    begin
        return nvl(config_pkg.get_config('MAP.COLOUR.' || p_colour), p_colour);
    end;

    function existing_skus(p_style in varchar2) return clob is
        l_status number;
        l_body clob;
        l_arr json_array_t;
        l_row json_object_t;
        l_out json_object_t := json_object_t();
        l_skus json_array_t := json_array_t();
        l_sku json_object_t;
    begin
        l_body := client_pkg.get_json(
            '/RmsReSTServices/services/private/Item/itemDetail?item=' || p_style, l_status);

        if l_status not between 200 and 299 then
            l_out.put('available', false);
            l_out.put('skus', json_array_t());
            l_out.put('message', 'itemDetail returned HTTP ' || l_status);
            return l_out.to_clob;
        end if;

        l_arr := json_array_t.parse(l_body);
        for i in 0 .. l_arr.get_size - 1 loop
            l_row := treat(l_arr.get(i) as json_object_t);
            -- The response is not ordered parent-first, so match the relationship.
            if l_row.get_string('itemParent') = p_style then
                l_sku := json_object_t();
                l_sku.put('item', l_row.get_string('item'));
                l_sku.put('diff1', l_row.get_string('diff1'));
                l_sku.put('diff2', l_row.get_string('diff2'));
                l_sku.put('status', l_row.get_string('status'));
                l_skus.append(l_sku);
            end if;
        end loop;

        l_out.put('available', true);
        l_out.put('skus', l_skus);
        return l_out.to_clob;
    exception
        when others then
            l_out := json_object_t();
            l_out.put('available', false);
            l_out.put('skus', json_array_t());
            l_out.put('message', substr(sqlerrm, 1, 300));
            return l_out.to_clob;
    end;

    function resolve_gap(
        p_style  in varchar2,
        p_colour in varchar2,
        p_sizes  in varchar2
    ) return clob is
        l_root json_object_t := json_object_t();
        l_existing json_object_t;
        l_skus json_array_t;
        l_sku json_object_t;
        l_required json_array_t := json_array_t();
        l_missing json_array_t := json_array_t();
        l_entry json_object_t;
        l_colour_diff varchar2(120) := colour_diff(p_colour);
        l_sizes apex_t_varchar2;
        l_size_diff varchar2(120);
        l_match varchar2(30);
        l_have number := 0;
    begin
        l_root.put('style', p_style);
        l_root.put('colour', p_colour);
        l_root.put('colourDiff', l_colour_diff);

        l_existing := json_object_t.parse(existing_skus(p_style));
        if not l_existing.get_boolean('available') then
            l_root.put('resolved', false);
            l_root.put('message', l_existing.get_string('message'));
            return l_root.to_clob;
        end if;
        l_skus := l_existing.get_array('skus');

        l_sizes := apex_string.split(p_sizes, ':');
        for i in 1 .. l_sizes.count loop
            if l_sizes(i) is not null then
                l_size_diff := size_diff(l_sizes(i));
                l_match := null;

                -- A SKU matches only when BOTH diffs match. Same colour, different
                -- size is a different SKU, and so is the reverse.
                for j in 0 .. l_skus.get_size - 1 loop
                    l_sku := treat(l_skus.get(j) as json_object_t);
                    if l_sku.get_string('diff1') = l_colour_diff
                       and l_sku.get_string('diff2') = l_size_diff then
                        l_match := l_sku.get_string('item');
                        exit;
                    end if;
                end loop;

                l_entry := json_object_t();
                l_entry.put('size', l_sizes(i));
                l_entry.put('sizeDiff', l_size_diff);
                l_entry.put('colourDiff', l_colour_diff);
                l_entry.put('sku', l_match);
                l_entry.put('mappingFound', l_size_diff is not null);
                l_entry.put('status', case when l_match is not null then 'EXISTS' else 'MISSING' end);
                l_required.append(l_entry);

                if l_match is not null then
                    l_have := l_have + 1;
                else
                    l_missing.append(l_entry);
                end if;
            end if;
        end loop;

        l_root.put('resolved', true);
        l_root.put('existingSkuCount', l_skus.get_size);
        l_root.put('required', l_required);
        l_root.put('missing', l_missing);
        l_root.put('haveCount', l_have);
        l_root.put('missingCount', l_missing.get_size);
        l_root.put('complete', l_missing.get_size = 0);
        l_root.put('note',
            case when l_missing.get_size = 0
                 then 'The style already carries every colour/size combination this request needs.'
                 else 'A colour change cannot be applied to an existing SKU - MFCS returns SUCCESS '
                      || 'and ignores it. The missing combinations must be created as new children '
                      || 'before the request can proceed.'
            end);
        return l_root.to_clob;
    end;

    function style_attributes(p_style in varchar2) return clob is
        l_status number;
        l_body clob;
        l_arr json_array_t;
        l_row json_object_t;
        l_item json_object_t;
        l_suppliers json_array_t;
        l_supplier json_object_t;
        l_countries json_array_t;
        l_country json_object_t;
        l_out json_object_t := json_object_t();

        -- json_object_t.put stores an explicit null for a null bind, which then reads
        -- back as present-but-null. Absent is the honest answer when the tenant did
        -- not send the field, and it is what lets the payload builders fall back to
        -- configuration for the few attributes itemDetail does not carry.
        procedure put_str(p_name in varchar2, p_value in varchar2) is
        begin
            if p_value is not null then
                l_out.put(p_name, p_value);
            end if;
        end;

        procedure put_num(p_name in varchar2, p_value in number) is
        begin
            if p_value is not null then
                l_out.put(p_name, p_value);
            end if;
        end;
    begin
        l_body := client_pkg.get_json(
            '/RmsReSTServices/services/private/Item/itemDetail?item=' || p_style, l_status);

        if l_status not between 200 and 299 then
            l_out.put('available', false);
            l_out.put('message', 'itemDetail returned HTTP ' || l_status);
            return l_out.to_clob;
        end if;

        l_arr := json_array_t.parse(l_body);
        for i in 0 .. l_arr.get_size - 1 loop
            l_row := treat(l_arr.get(i) as json_object_t);
            -- The parent is the row that is the item itself; the rest are its
            -- children. The array is not ordered parent-first.
            if l_row.get_string('item') = p_style then
                l_item := l_row;
                exit;
            end if;
        end loop;

        if l_item is null then
            l_out.put('available', false);
            l_out.put('message', 'itemDetail returned no row for item ' || p_style);
            return l_out.to_clob;
        end if;

        l_out.put('available', true);
        put_str('item', l_item.get_string('item'));
        put_num('itemLevel', l_item.get_number('itemLevel'));
        put_num('dept', l_item.get_number('dept'));
        -- classAttribute, not class: itemDetail is a third vocabulary again, after
        -- the item feed's and the write services'. See the header comment.
        put_num('class', l_item.get_number('classAttribute'));
        put_num('subclass', l_item.get_number('subclass'));
        put_str('status', l_item.get_string('status'));
        put_num('originalRetail', l_item.get_number('originalRetail'));
        put_str('itemDescription', l_item.get_string('itemDesc'));
        put_str('shortDescription', l_item.get_string('shortDesc'));

        -- Take the primary supplier, falling back to the first row present. A style
        -- with no supplier at all is legitimate here: the caller decides whether the
        -- inbound document covers the gap.
        if l_item.has('itemSupplier') then
            l_suppliers := l_item.get_array('itemSupplier');
            for i in 0 .. nvl(l_suppliers.get_size, 0) - 1 loop
                l_supplier := treat(l_suppliers.get(i) as json_object_t);
                if i = 0 or nvl(l_supplier.get_string('primarySuppInd'), 'N') = 'Y' then
                    put_num('supplier', l_supplier.get_number('supplier'));

                    if l_supplier.has('itemSupplierCountry') then
                        l_countries := l_supplier.get_array('itemSupplierCountry');
                        for j in 0 .. nvl(l_countries.get_size, 0) - 1 loop
                            l_country := treat(l_countries.get(j) as json_object_t);
                            if j = 0 or nvl(l_country.get_string('primaryCountryInd'), 'N') = 'Y' then
                                put_str('originCountry', l_country.get_string('originCountryId'));
                                put_num('unitCost', l_country.get_number('unitCost'));
                            end if;
                        end loop;
                    end if;
                end if;
            end loop;
        end if;

        return l_out.to_clob;
    exception
        when others then
            l_out := json_object_t();
            l_out.put('available', false);
            l_out.put('message', substr(sqlerrm, 1, 300));
            return l_out.to_clob;
    end;
end sku_pkg;
/

show errors
