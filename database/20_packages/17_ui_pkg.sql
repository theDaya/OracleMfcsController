set define off

prompt Creating ui_pkg

create or replace package ui_pkg authid definer as
    function new_action_request_id return varchar2;

    function build_document(p_draft_id in number) return clob;

    procedure validate_draft(
        p_draft_id     in number,
        o_http_status  out number,
        o_response     out clob
    );

    procedure preview_draft(
        p_draft_id     in number,
        o_http_status  out number,
        o_response     out clob
    );

    procedure submit_draft(
        p_draft_id     in number,
        o_http_status  out number,
        o_response     out clob
    );

    procedure submit_job(p_draft_id in number);

    procedure enqueue_submit(p_draft_id in number);

    procedure refresh_status(p_draft_id in number);
end ui_pkg;
/
show errors

create or replace package body ui_pkg as
    function new_action_request_id return varchar2 is
    begin
        return 'APEX-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
    end;

    function build_document(p_draft_id in number) return clob is
        l_payload clob;
    begin
        select json_object(
                   'ACTION_REQUEST_ID' value d.action_request_id,
                   'OPERATION_NAME' value d.operation_name,
                   'SOURCE_SYSTEM' value d.source_system,
                   'SOURCE_STYLE_REF' value d.source_style_ref,
                   'SOURCE_ORDER_REF' value d.source_order_ref,
                   'SOURCE_VERSION' value d.source_version,
                   'USER_ID' value d.user_id,
                   'DESCRIPTION' value d.description,
                   -- Generated IDs are persisted on the draft for tracking, but create
                   -- requests must keep their outbound payload shape idempotent.
                   'STYLE' value case when d.operation_name in ('CREATE_STYLE', 'CREATE_ALL') then null else d.style end,
                   'ORDER_NO' value case when d.operation_name in ('CREATE_STYLE', 'CREATE_ORDER', 'CREATE_ALL') then null else d.order_no end,
                   'DEPARTMENT' value d.department,
                   'CLASS' value d.class,
                   'SUBCLASS' value d.subclass,
                   'SUPPLIER' value d.supplier,
                   'ORIGIN_COUNTRY' value d.origin_country,
                   'IMPORT_COUNTRY' value d.import_country,
                   'CURRENCY_CODE' value d.currency_code,
                   'COLOUR' value d.colour,
                   'UNIT_COST' value d.unit_cost,
                   'RETAIL_PRICE' value d.retail_price,
                   'SIZE_CURVE_DETAIL' value (
                       select coalesce(
                                  json_arrayagg(
                                      json_object(
                                          'SOURCE_VARIANT_REF' value substr(
                                              coalesce(
                                                  s.source_variant_ref,
                                                  d.source_style_ref || ':' || s.sku_size || ':' || nvl(s.sku_width, 'ALL')
                                              ),
                                              1,
                                              120
                                          ),
                                          'SKU_SIZE' value s.sku_size,
                                          'SKU_WIDTH' value s.sku_width,
                                          'SKU_QTY' value s.sku_qty,
                                          'SKU_ID' value case when d.operation_name in ('CREATE_STYLE', 'CREATE_ALL') then null else s.sku_id end,
                                          -- Absent, not empty, when the SKU has no
                                          -- barcodes. The backend treats a missing
                                          -- SKU_UPCS and an empty one the same, but
                                          -- an absent key says "none captured"
                                          -- rather than "none, deliberately".
                                          'SKU_UPCS' value (
                                              select json_arrayagg(
                                                         json_object(
                                                             'UPC' value u.upc,
                                                             'UPC_TYPE' value u.upc_type,
                                                             'PRIMARY_YN' value u.primary_yn
                                                         absent on null returning clob)
                                                         order by u.primary_yn desc, u.draft_upc_id
                                                         returning clob
                                                     )
                                                from ui_draft_sku_upc u
                                               where u.draft_sku_id = s.draft_sku_id
                                          ) format json
                                      absent on null returning clob)
                                      order by s.draft_sku_id
                                      returning clob
                                  ),
                                  to_clob('[]')
                              )
                         from ui_draft_sku s
                        where s.draft_id = d.draft_id
                   ) format json,
                   'STYLE_SEASONS' value (
                       select json_arrayagg(
                                  json_object(
                                      'SEASON_ID' value sn.season_id,
                                      'PHASE_ID' value sn.phase_id,
                                      'SEQUENCE_NO' value sn.sequence_no
                                  absent on null returning clob)
                                  order by sn.season_id returning clob)
                         from ui_draft_season sn
                        where sn.draft_id = d.draft_id
                   ) format json,
                   'STYLE_IMAGES' value (
                       select json_arrayagg(
                                  json_object(
                                      'IMAGE_NAME' value im.image_name,
                                      'IMAGE_ADDRESS' value im.image_address,
                                      'IMAGE_DESCRIPTION' value im.image_description,
                                      'IMAGE_TYPE' value im.image_type,
                                      'PRIMARY_YN' value im.primary_yn,
                                      'DISPLAY_PRIORITY' value im.display_priority
                                  absent on null returning clob)
                                  order by im.primary_yn desc, im.display_priority, im.draft_image_id
                                  returning clob)
                         from ui_draft_image im
                        where im.draft_id = d.draft_id
                   ) format json,
                   'STYLE_HTS' value (
                       select json_arrayagg(
                                  json_object(
                                      'HTS' value h.hts,
                                      'IMPORT_COUNTRY' value h.import_country,
                                      'ORIGIN_COUNTRY' value h.origin_country,
                                      'EFFECT_FROM' value to_char(h.effect_from, 'YYYY-MM-DD'),
                                      'EFFECT_TO' value to_char(h.effect_to, 'YYYY-MM-DD')
                                  absent on null returning clob)
                                  order by h.hts returning clob)
                         from ui_draft_hts h
                        where h.draft_id = d.draft_id
                   ) format json,
                   -- Style level only. SKUs inherit these, so the console has no
                   -- SKU-level UDA capture and the backend writes the same set to
                   -- the parent and every child.
                   'STYLE_UDAS' value (
                       select json_arrayagg(
                                  json_object(
                                      'UDA_ID' value ud.uda_id,
                                      'UDA_VALUE' value ud.uda_value,
                                      'UDA_TEXT' value ud.uda_text,
                                      'UDA_DATE' value to_char(ud.uda_date, 'YYYY-MM-DD')
                                  absent on null returning clob)
                                  order by ud.uda_id
                                  returning clob
                              )
                         from ui_draft_uda ud
                        where ud.draft_id = d.draft_id
                   ) format json,
                   'NOT_BEFORE_DATE' value to_char(d.not_before_date, 'YYYY-MM-DD'),
                   'NOT_AFTER_DATE' value to_char(d.not_after_date, 'YYYY-MM-DD'),
                   'OTB_EOW_DATE' value to_char(d.otb_eow_date, 'YYYY-MM-DD'),
                   'EARLIEST_SHIP_DATE' value to_char(d.earliest_ship_date, 'YYYY-MM-DD'),
                   'LATEST_SHIP_DATE' value to_char(d.latest_ship_date, 'YYYY-MM-DD'),
                   'DELIVERY_LOC' value d.delivery_loc,
                   'ORDER_EXCHANGE_RATE' value d.order_exchange_rate,
                   'CANCEL_CODE' value d.cancel_code,
                   'ORDER_AMEND_MSG' value d.order_amend_msg
                   returning clob
               )
          into l_payload
          from ui_draft d
         where d.draft_id = p_draft_id;

        update ui_draft
           set request_payload = l_payload,
               updated_at = systimestamp
         where draft_id = p_draft_id;

        return l_payload;
    exception
        when no_data_found then
            raise_application_error(-20910, 'UI draft not found: ' || p_draft_id);
    end;

    procedure save_result(
        p_draft_id     in number,
        p_http_status  in number,
        p_response     in clob,
        p_status       in varchar2,
        p_preview      in boolean default false
    ) is
    begin
        update ui_draft
           set http_status = p_http_status,
               response_payload = case when p_preview then response_payload else p_response end,
               preview_payload = case when p_preview then p_response else preview_payload end,
               draft_status = p_status,
               updated_at = systimestamp
         where draft_id = p_draft_id;
    end;

    procedure sync_generated_identifiers(p_draft_id in number) is
        l_action_request_id ui_draft.action_request_id%type;
        l_style ui_draft.style%type;
        l_order_no ui_draft.order_no%type;
        l_sku_count number := 0;
    begin
        select d.action_request_id,
               coalesce(
                   r.style_no,
                   json_value(r.response_payload, '$.STYLE' returning varchar2(30) null on error),
                   json_value(d.response_payload, '$.STYLE' returning varchar2(30) null on error),
                   d.style
               ),
               coalesce(
                   r.order_no,
                   json_value(r.response_payload, '$.ORDER_NO' returning varchar2(30) null on error),
                   json_value(d.response_payload, '$.ORDER_NO' returning varchar2(30) null on error),
                   d.order_no
               )
          into l_action_request_id, l_style, l_order_no
          from ui_draft d
          left join request r
            on r.action_request_id = d.action_request_id
         where d.draft_id = p_draft_id;

        update ui_draft
           set style = l_style,
               order_no = l_order_no,
               updated_at = systimestamp
         where draft_id = p_draft_id
           and (
               nvl(style, '-') <> nvl(l_style, '-')
               or nvl(order_no, '-') <> nvl(l_order_no, '-')
           );

        merge into ui_draft_sku s
        using (
            select draft_sku_id,
                   source_variant_ref,
                   mfcs_sku_no
              from (
                    select s.draft_sku_id,
                           m.source_variant_ref,
                           m.mfcs_sku_no,
                           row_number() over (
                               partition by s.draft_sku_id
                               order by case
                                            when s.source_variant_ref is not null
                                             and m.source_variant_ref = s.source_variant_ref then 0
                                            when s.source_variant_ref is null
                                             and m.source_variant_ref = substr(d.source_style_ref || ':' || s.sku_size || ':' || nvl(s.sku_width, 'ALL'), 1, 120) then 1
                                            else 2
                                        end,
                                        m.last_updated_at desc
                           ) rn
                      from ui_draft d
                      join ui_draft_sku s
                        on s.draft_id = d.draft_id
                      join entity_map m
                        on m.source_system = d.source_system
                       and nvl(m.source_style_ref, '-') = nvl(d.source_style_ref, '-')
                       and m.mfcs_sku_no is not null
                     where d.draft_id = p_draft_id
                       and (
                           nvl(m.source_variant_ref, '-') = nvl(s.source_variant_ref, '-')
                           or (
                               s.source_variant_ref is null
                               and m.source_variant_ref = substr(d.source_style_ref || ':' || s.sku_size || ':' || nvl(s.sku_width, 'ALL'), 1, 120)
                           )
                           or (
                               m.sku_size = s.sku_size
                               and nvl(m.sku_width, 'ALL') = nvl(s.sku_width, 'ALL')
                           )
                       )
                   )
             where rn = 1
        ) m
        on (s.draft_sku_id = m.draft_sku_id)
        when matched then update
             set s.source_variant_ref = coalesce(s.source_variant_ref, m.source_variant_ref),
                 s.sku_id = coalesce(m.mfcs_sku_no, s.sku_id),
                 s.updated_at = systimestamp
           where nvl(s.source_variant_ref, '-') <> nvl(m.source_variant_ref, '-')
              or nvl(s.sku_id, '-') <> nvl(m.mfcs_sku_no, '-');

        l_sku_count := sql%rowcount;

        if l_style is not null or l_order_no is not null or l_sku_count > 0 then
            event_pkg.log_event(
                p_action_request_id => l_action_request_id,
                p_event_phase => 'UI_DRAFT_IDENTIFIERS_SYNCED',
                p_message => 'Generated MFCS identifiers persisted back to the UI draft.',
                p_detail_payload => '{"draftId":' || to_char(p_draft_id)
                    || ',"style":' || case when l_style is null then 'null' else '"' || event_pkg.escape_json(l_style) || '"' end
                    || ',"orderNo":' || case when l_order_no is null then 'null' else '"' || event_pkg.escape_json(l_order_no) || '"' end
                    || ',"skuRows":' || to_char(l_sku_count) || '}'
            );
        end if;
    exception
        when no_data_found then
            null;
    end;

    procedure validate_draft(
        p_draft_id     in number,
        o_http_status  out number,
        o_response     out clob
    ) is
        l_payload clob;
    begin
        l_payload := build_document(p_draft_id);
        api_pkg.validate_transaction(l_payload, o_http_status, o_response);
        save_result(
            p_draft_id,
            o_http_status,
            o_response,
            case when o_http_status between 200 and 299 then 'VALID' else 'INVALID' end
        );
        commit;
    end;

    procedure preview_draft(
        p_draft_id     in number,
        o_http_status  out number,
        o_response     out clob
    ) is
        l_payload clob;
    begin
        l_payload := build_document(p_draft_id);
        preview_pkg.preview_transaction(l_payload, o_http_status, o_response);
        save_result(
            p_draft_id,
            o_http_status,
            o_response,
            case when o_http_status between 200 and 299 then 'PREVIEWED' else 'INVALID' end,
            true
        );
        commit;
    end;

    procedure refresh_status(p_draft_id in number) is
        l_action_request_id ui_draft.action_request_id%type;
        l_status request.request_status%type;
        l_response request.response_payload%type;
    begin
        select action_request_id into l_action_request_id
          from ui_draft
         where draft_id = p_draft_id;

        select request_status, response_payload
          into l_status, l_response
          from request
         where action_request_id = l_action_request_id;

        update ui_draft
           set draft_status = case
                                  when l_status = 'COMPLETED' then 'COMPLETED'
                                  when l_status = 'PARTIALLY_COMPLETED' then 'PARTIALLY_COMPLETED'
                                  when l_status like 'FAILED%' then 'FAILED'
                                  else draft_status
                              end,
               response_payload = coalesce(l_response, response_payload),
               updated_at = systimestamp
         where draft_id = p_draft_id;

        sync_generated_identifiers(p_draft_id);
    exception
        when no_data_found then
            null;
    end;

    procedure submit_draft(
        p_draft_id     in number,
        o_http_status  out number,
        o_response     out clob
    ) is
        l_payload clob;
        l_stored_hash varchar2(64);
        l_new_hash varchar2(64);
    begin
        l_payload := build_document(p_draft_id);

        -- Submit whatever the draft says now, not what it said when it first ran.
        --
        -- An unchanged draft keeps its ACTION_REQUEST_ID, which is what makes a
        -- resubmit a resume: completed steps are skipped and the run picks up
        -- where it stopped. An edited draft is a different request wearing the
        -- same id, and the API rightly answers 409 - so it gets a new id here
        -- and goes in as a fresh request. Either way the buyer presses one
        -- button and the thing they are looking at is what gets sent.
        l_new_hash := request_pkg.payload_hash(l_payload);
        begin
            select r.payload_hash
              into l_stored_hash
              from request r, ui_draft d
             where d.draft_id = p_draft_id
               and r.action_request_id = d.action_request_id;
        exception
            when no_data_found then
                l_stored_hash := null;
        end;

        if l_stored_hash is not null and l_stored_hash <> l_new_hash then
            update ui_draft
               set action_request_id = new_action_request_id,
                   updated_at = systimestamp
             where draft_id = p_draft_id;
            commit;
            l_payload := build_document(p_draft_id);
        end if;

        api_pkg.submit_transaction(l_payload, o_http_status, o_response);

        update ui_draft
           set http_status = o_http_status,
               response_payload = o_response,
               draft_status = case
                                  when o_http_status between 200 and 299 then 'COMPLETED'
                                  when o_http_status = 502 then 'PARTIALLY_COMPLETED'
                                  else 'FAILED'
                              end,
               submitted_at = coalesce(submitted_at, systimestamp),
               updated_at = systimestamp
         where draft_id = p_draft_id;
        refresh_status(p_draft_id);
        commit;
    end;

    procedure submit_job(p_draft_id in number) is
        l_status number;
        l_response clob;
        l_error varchar2(4000);
    begin
        submit_draft(p_draft_id, l_status, l_response);
    exception
        when others then
            l_error := sqlerrm;
            update ui_draft
               set draft_status = 'FAILED',
                   response_payload = json_object(
                       'status' value 'FAILED',
                       'message' value l_error
                       returning clob
                   ),
                   updated_at = systimestamp
             where draft_id = p_draft_id;
            commit;
            raise;
    end;

    procedure enqueue_submit(p_draft_id in number) is
        l_job varchar2(128);
    begin
        update ui_draft
           set draft_status = 'SUBMITTED',
               submitted_at = coalesce(submitted_at, systimestamp),
               updated_at = systimestamp
         where draft_id = p_draft_id;
        commit;

        l_job := 'MFCS_UI_SUBMIT_' || p_draft_id || '_' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3');
        dbms_scheduler.create_job(
            job_name   => l_job,
            job_type   => 'PLSQL_BLOCK',
            job_action => 'begin ui_pkg.submit_job(' || to_char(p_draft_id) || '); end;',
            enabled    => true,
            auto_drop  => true
        );
    end;
end ui_pkg;
/
show errors
