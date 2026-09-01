-- Offline checks for the UDA and barcode mappers, and the validation that guards
-- them. Makes no tenant call and creates no MFCS record; it writes a throwaway
-- REQUEST and ENTITY_MAP row on this database and removes them again.
--
--   deploy/mdutils/sql.sh tests/payload_mapper_tests.sql
--
-- The cleanup runs at both ends on purpose. step_pkg.initialize_steps commits, so
-- a rollback at the end of the block does not undo the rows inserted before it.
--
-- What it is watching for, beyond "does it run":
--
--   The UDA payload must cover the style AND every SKU. SKUs inherit their style's
--   UDAs and MFCS is not known to cascade, so both levels are written explicitly.
--
--   displayType must follow the value: LV -> udaValue, FF -> udaText, DT -> udaDate.
--   MFCS rejects a uda row without it.
--
--   The barcode payload must contain only real barcodes. json_table's nested path
--   is an outer join, so a SKU with no SKU_UPCS once produced a level-3 item with a
--   null item number - collectionSize is the assertion that catches its return.

set serveroutput on size unlimited
set pagesize 0 feedback off heading off linesize 400

declare
    l_id varchar2(60) := 'MAPPER-TEST-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
    l_payload clob;
    l_out clob;
    l_errors clob;
    l_ok boolean;

    procedure show(p_label in varchar2, p_clob in clob) is
        l_len number := nvl(length(p_clob), 0);
    begin
        dbms_output.put_line('--- ' || p_label || ' (' || l_len || ' chars) ---');
        for i in 0 .. trunc((l_len - 1) / 300) loop
            dbms_output.put_line(substr(p_clob, i * 300 + 1, 300));
        end loop;
    end;
begin
    -- step_pkg.initialize_steps commits, so a previous run's rows survive its
    -- rollback. Clear them first and clear them again at the end.
    delete from step where action_request_id like 'MAPPER-TEST-%';
    delete from request where action_request_id like 'MAPPER-TEST-%';
    delete from entity_map where source_style_ref = 'mapper test style';
    commit;

    l_payload := '{
      "ACTION_REQUEST_ID": "' || l_id || '",
      "OPERATION_NAME": "CREATE_STYLE",
      "SOURCE_SYSTEM": "OFFICE_DEV",
      "SOURCE_STYLE_REF": "mapper test style",
      "SOURCE_VERSION": "1",
      "DESCRIPTION": "mapper test",
      "DEPARTMENT": "1517", "CLASS": "6892", "SUBCLASS": "1128",
      "SUPPLIER": "700087", "ORIGIN_COUNTRY": "GB", "CURRENCY_CODE": "ZAR",
      "COLOUR": "08610", "UNIT_COST": 48.49, "RETAIL_PRICE": 100,
      "STYLE_SEASONS": [ { "SEASON_ID": 1, "PHASE_ID": 1, "SEQUENCE_NO": 1 } ],
      "STYLE_IMAGES": [ { "IMAGE_NAME": "100150161_sd1.jpg",
                          "IMAGE_ADDRESS": "https://cdn.media.amplience.net/i/office/",
                          "PRIMARY_YN": "Y", "DISPLAY_PRIORITY": 1 } ],
      "STYLE_HTS": [ { "HTS": "6402993900", "IMPORT_COUNTRY": "GB",
                       "ORIGIN_COUNTRY": "DE",
                       "EFFECT_FROM": "2026-01-01", "EFFECT_TO": "2049-01-01" } ],
      "STYLE_UDAS": [
        { "UDA_ID": 239, "UDA_VALUE": "3" },
        { "UDA_ID": 51040, "UDA_TYPE": "FF", "UDA_TEXT": "Leather upper" }
      ],
      "SIZE_CURVE_DETAIL": [
        { "SOURCE_VARIANT_REF": "mapper test style-7", "SKU_SIZE": "070",
          "SKU_WIDTH": "ALL", "SKU_QTY": 1, "SKU_ID": null,
          "SKU_UPCS": [
            { "UPC": "2930000003016", "PRIMARY_YN": "Y" },
            { "UPC": "4013871023272", "PRIMARY_YN": "N", "UPC_TYPE": "MANL" }
          ] },
        { "SOURCE_VARIANT_REF": "mapper test style-8", "SKU_SIZE": "080",
          "SKU_WIDTH": "ALL", "SKU_QTY": 1, "SKU_ID": null }
      ]
    }';

    dbms_output.put_line('=== 1. VALIDATION of a good document ===');
    l_ok := validation_pkg.validate_request(l_payload, l_errors);
    dbms_output.put_line('valid = ' || case when l_ok then 'TRUE' else 'FALSE' end);
    if not l_ok then
        show('errors', l_errors);
    end if;

    insert into request (action_request_id, operation_name, source_system,
                         source_style_ref, source_version, request_status,
                         style_no, payload_hash, request_payload)
    values (l_id, 'CREATE_STYLE', 'OFFICE_DEV', 'mapper test style', '1',
            'RECEIVED', '100150111', 'mapper-test-hash', l_payload);

    -- Give the two SKUs numbers, as the reservation step would.
    insert into entity_map (source_system, source_style_ref, mfcs_style_no,
                            source_variant_ref, mfcs_sku_no, sku_size, sku_width)
    values ('OFFICE_DEV', 'mapper test style', '100150111',
            'mapper test style-7', '100150129', '7', 'ALL');
    insert into entity_map (source_system, source_style_ref, mfcs_style_no,
                            source_variant_ref, mfcs_sku_no, sku_size, sku_width)
    values ('OFFICE_DEV', 'mapper test style', '100150111',
            'mapper test style-8', '100150130', '8', 'ALL');

    dbms_output.put_line('');
    dbms_output.put_line('=== 2. build_item_uda_request ===');
    l_out := payload_pkg.build_request(l_id, 'build_item_uda_request');
    show('uda payload', l_out);

    dbms_output.put_line('');
    dbms_output.put_line('=== 3. build_reference_item_request ===');
    l_out := payload_pkg.build_request(l_id, 'build_reference_item_request');
    show('reference item payload', l_out);

    dbms_output.put_line('');
    dbms_output.put_line('=== 3b. season / image / hts mappers ===');
    for m in (select 'build_item_season_request' n, 'season' k from dual union all
              select 'build_item_image_request', 'image' from dual union all
              select 'build_item_hts_request', 'hts' from dual) loop
        l_out := payload_pkg.build_request(l_id, m.n);
        dbms_output.put_line(rpad(m.n, 30)
            || ' collectionSize=' || json_value(l_out, '$.collectionSize')
            || '  first=' || substr(json_query(l_out, '$.items[0].' || m.k), 1, 120));
    end loop;

    dbms_output.put_line('');
    dbms_output.put_line('=== 4. step graph for CREATE_STYLE ===');
    step_pkg.initialize_steps(l_id, 'CREATE_STYLE');
    for r in (select step_code, step_sequence from step
               where action_request_id = l_id order by step_sequence) loop
        dbms_output.put_line('   ' || lpad(r.step_sequence, 4) || '  ' || r.step_code);
    end loop;

    delete from step where action_request_id like 'MAPPER-TEST-%';
    delete from request where action_request_id like 'MAPPER-TEST-%';
    delete from entity_map where source_style_ref = 'mapper test style';
    commit;
    dbms_output.put_line('');
    dbms_output.put_line('(test rows removed)');
end;
/

declare
    l_errors clob;
    l_ok boolean;
    l_bad clob;
begin
    dbms_output.put_line('');
    dbms_output.put_line('=== 5. VALIDATION catches a bad barcode and two primaries ===');
    l_bad := '{
      "ACTION_REQUEST_ID": "BAD-1", "OPERATION_NAME": "CREATE_STYLE",
      "SOURCE_SYSTEM": "OFFICE_DEV", "SOURCE_STYLE_REF": "bad", "SOURCE_VERSION": "1",
      "DEPARTMENT": "1517", "CLASS": "6892", "SUBCLASS": "1128",
      "SUPPLIER": "700087", "ORIGIN_COUNTRY": "GB", "COLOUR": "08610",
      "SIZE_CURVE_DETAIL": [
        { "SOURCE_VARIANT_REF": "bad-7", "SKU_SIZE": "070", "SKU_WIDTH": "ALL", "SKU_QTY": 1,
          "SKU_UPCS": [
            { "UPC": "2930000003017", "PRIMARY_YN": "Y" },
            { "UPC": "2930000003016", "PRIMARY_YN": "Y" }
          ] }
      ]
    }';
    l_ok := validation_pkg.validate_request(l_bad, l_errors);
    dbms_output.put_line('valid = ' || case when l_ok then 'TRUE' else 'FALSE' end);
    for i in 0 .. trunc((nvl(length(l_errors), 1) - 1) / 300) loop
        dbms_output.put_line(substr(l_errors, i * 300 + 1, 300));
    end loop;
end;
/

-- Intake normalisation. The old key has to keep working: resume replays the
-- stored payload, so a document accepted before the rename must still run.
declare
    l_out clob;
    procedure check_it(p_label in varchar2, p_expected in varchar2, p_actual in varchar2) is
    begin
        dbms_output.put_line(rpad(p_label, 46)
            || case when nvl(p_actual, '<null>') = p_expected then 'PASS' else
                    'FAIL (expected ' || p_expected || ', got ' || nvl(p_actual, '<null>') || ')' end);
    end;
begin
    dbms_output.put_line('');
    dbms_output.put_line('=== 6. INTAKE NORMALISATION ===');

    l_out := request_pkg.normalise_payload(
        '{"DEPARTMENT":"1517","CLASS":"6892","SUBCLASS":"1128",
          "PLMSizeCurveDtl":[{"SKU_SIZE":"070","SKU_QTY":1}]}');
    check_it('legacy key becomes canonical',
        '1', to_char(case when json_exists(l_out, '$.SIZE_CURVE_DETAIL') then 1 else 0 end));
    check_it('legacy key is gone',
        '0', to_char(case when json_exists(l_out, '$.PLMSizeCurveDtl') then 1 else 0 end));
    check_it('size curve survives the rename',
        '070', json_value(l_out, '$.SIZE_CURVE_DETAIL[0].SKU_SIZE'));
    -- Asserted against the serialised text. json_value would coerce "1517" to
    -- 1517 and report a pass whether or not normalisation did anything.
    check_it('DEPARTMENT serialises unquoted',
        'Y', case when instr(l_out, '"DEPARTMENT":1517') > 0 then 'Y' else 'N' end);
    check_it('DEPARTMENT is no longer a string',
        'Y', case when instr(l_out, '"DEPARTMENT":"1517"') = 0 then 'Y' else 'N' end);

    l_out := request_pkg.normalise_payload(
        '{"SIZE_CURVE_DETAIL":[{"SKU_SIZE":"090"}],"PLMSizeCurveDtl":[{"SKU_SIZE":"070"}]}');
    check_it('canonical wins when both are sent',
        '090', json_value(l_out, '$.SIZE_CURVE_DETAIL[0].SKU_SIZE'));
    check_it('legacy dropped when both are sent',
        '0', to_char(case when json_exists(l_out, '$.PLMSizeCurveDtl') then 1 else 0 end));

    -- A non-numeric department is validation's problem to report, not something
    -- normalisation should fail the request over.
    l_out := request_pkg.normalise_payload('{"DEPARTMENT":"not-a-number"}');
    check_it('non-numeric DEPARTMENT is left alone',
        'not-a-number', json_value(l_out, '$.DEPARTMENT'));

    l_out := request_pkg.normalise_payload('{ this is not json');
    check_it('unparseable payload passes through untouched',
        '{ this is not json', l_out);
end;
/
