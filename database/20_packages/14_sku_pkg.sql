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
end sku_pkg;
/

show errors
