set define off

-- Request lifecycle: registration, idempotency hashing, status and generated identifiers.

prompt Creating request_pkg

create or replace package request_pkg authid definer as
    function payload_hash(p_payload in clob) return varchar2;

    procedure register_request(
        p_action_request_id in varchar2,
        p_operation_name    in varchar2,
        p_payload_hash      in varchar2,
        p_payload           in clob,
        o_result            out varchar2,
        o_status            out varchar2,
        o_response_payload  out clob
    );

    procedure set_request_status(
        p_action_request_id in varchar2,
        p_status            in varchar2,
        p_response_payload  in clob default null
    );

    procedure save_generated_identifier(
        p_action_request_id   in varchar2,
        p_source_system       in varchar2,
        p_source_style_ref    in varchar2,
        p_mfcs_style_no       in varchar2,
        p_source_variant_ref  in varchar2 default null,
        p_mfcs_sku_no         in varchar2 default null,
        p_sku_size            in varchar2 default null,
        p_sku_width           in varchar2 default null,
        p_source_order_ref    in varchar2 default null,
        p_mfcs_order_no       in varchar2 default null
    );

    function build_status_response(
        p_action_request_id in varchar2,
        p_status_override   in varchar2 default null
    ) return clob;
end request_pkg;
/

show errors

create or replace package body request_pkg as
    function json_escape(p_value in varchar2) return varchar2 is
    begin
        if p_value is null then
            return null;
        end if;

        return replace(
                   replace(
                       replace(
                           replace(p_value, '\', '\\'),
                           '"', '\"'
                       ),
                       chr(10), '\n'
                   ),
                   chr(13), '\r'
               );
    end;

    function canonicalize(p_element in json_element_t) return clob is
        l_object json_object_t;
        l_array json_array_t;
        l_keys json_key_list;
        l_key varchar2(4000);
        l_tmp varchar2(4000);
        l_result clob;
        l_first boolean := true;
    begin
        if p_element is null then
            return 'null';
        elsif p_element.is_object then
            l_object := treat(p_element as json_object_t);
            l_keys := l_object.get_keys;

            if l_keys is not null then
                for i in 1 .. l_keys.count loop
                    if i < l_keys.count then
                        for j in i + 1 .. l_keys.count loop
                            if l_keys(j) < l_keys(i) then
                                l_tmp := l_keys(i);
                                l_keys(i) := l_keys(j);
                                l_keys(j) := l_tmp;
                            end if;
                        end loop;
                    end if;
                end loop;
            end if;

            l_result := '{';
            if l_keys is not null then
                for i in 1 .. l_keys.count loop
                    l_key := l_keys(i);
                    if upper(l_key) not in ('DATE_TIME_STAMP', 'REQUEST_RECEIVED_AT', 'TRANSPORT_ID') then
                        if l_first then
                            l_first := false;
                        else
                            l_result := l_result || ',';
                        end if;

                        l_result := l_result
                            || '"' || json_escape(l_key) || '":'
                            || canonicalize(l_object.get(l_key));
                    end if;
                end loop;
            end if;
            l_result := l_result || '}';
            return l_result;
        elsif p_element.is_array then
            l_array := treat(p_element as json_array_t);
            l_result := '[';

            if l_array.get_size > 0 then
                for i in 0 .. l_array.get_size - 1 loop
                    if i > 0 then
                        l_result := l_result || ',';
                    end if;
                    l_result := l_result || canonicalize(l_array.get(i));
                end loop;
            end if;

            l_result := l_result || ']';
            return l_result;
        else
            return p_element.to_string;
        end if;
    end;

    function payload_hash(p_payload in clob) return varchar2 is
        l_element json_element_t;
        l_canonical clob;
        l_hash varchar2(64);
    begin
        l_element := json_element_t.parse(p_payload);
        l_canonical := canonicalize(l_element);

        l_hash := rawtohex(dbms_crypto.hash(l_canonical, dbms_crypto.hash_sh256));

        return lower(l_hash);
    end;

    procedure register_request(
        p_action_request_id in varchar2,
        p_operation_name    in varchar2,
        p_payload_hash      in varchar2,
        p_payload           in clob,
        o_result            out varchar2,
        o_status            out varchar2,
        o_response_payload  out clob
    ) is
        l_existing_hash varchar2(64);
        l_status varchar2(30);
        l_source_system varchar2(60);
        l_source_style_ref varchar2(120);
        l_source_order_ref varchar2(120);
        l_source_version varchar2(60);
        l_style_no varchar2(30);
        l_order_no varchar2(30);
    begin
        select json_value(p_payload, '$.SOURCE_SYSTEM' returning varchar2(60) null on error),
               json_value(p_payload, '$.SOURCE_STYLE_REF' returning varchar2(120) null on error),
               json_value(p_payload, '$.SOURCE_ORDER_REF' returning varchar2(120) null on error),
               json_value(p_payload, '$.SOURCE_VERSION' returning varchar2(60) null on error),
               json_value(p_payload, '$.STYLE' returning varchar2(30) null on error),
               json_value(p_payload, '$.ORDER_NO' returning varchar2(30) null on error)
          into l_source_system, l_source_style_ref, l_source_order_ref, l_source_version,
               l_style_no, l_order_no
          from dual;

        if l_style_no is null and l_source_system is not null and l_source_style_ref is not null then
            select max(mfcs_style_no)
              into l_style_no
              from entity_map
             where source_system = l_source_system
               and source_style_ref = l_source_style_ref
               and mfcs_style_no is not null;
        end if;

        if p_operation_name in ('CREATE_STYLE', 'MODIFY_STYLE') then
            l_order_no := null;
        end if;

        begin
            insert into request (
                action_request_id,
                operation_name,
                source_system,
                source_style_ref,
                source_order_ref,
                source_version,
                payload_hash,
                request_status,
                style_no,
                order_no,
                request_payload
            ) values (
                p_action_request_id,
                p_operation_name,
                l_source_system,
                l_source_style_ref,
                l_source_order_ref,
                l_source_version,
                p_payload_hash,
                'RECEIVED',
                l_style_no,
                l_order_no,
                p_payload
            );

            commit;
            o_result := 'NEW';
            o_status := 'RECEIVED';
            o_response_payload := null;
            return;
        exception
            when dup_val_on_index then
                null;
        end;

        begin
            select payload_hash, request_status, response_payload
              into l_existing_hash, l_status, o_response_payload
              from request
             where action_request_id = p_action_request_id
             for update nowait;
        exception
            when others then
                if sqlcode = -54 then
                    o_result := 'EXECUTING';
                    o_status := 'IN_PROGRESS';
                    o_response_payload := null;
                    rollback;
                    return;
                end if;
                raise;
        end;

        if l_existing_hash <> p_payload_hash then
            o_result := 'CONFLICT';
            o_status := l_status;
        elsif l_status = 'IN_PROGRESS' then
            o_result := 'EXECUTING';
            o_status := l_status;
        elsif l_status = 'FAILED_NO_SIDE_EFFECT'
              and o_response_payload is not null
              and dbms_lob.instr(o_response_payload, 'MFCS_BATCH_WINDOW_ACTIVE') > 0 then
            update request
               set request_status = 'IN_PROGRESS',
                   started_at = coalesce(started_at, systimestamp),
                   last_updated_at = systimestamp
             where action_request_id = p_action_request_id;
            o_result := 'RESUME';
            o_status := 'IN_PROGRESS';
        elsif l_status in ('COMPLETED', 'FAILED_NO_SIDE_EFFECT', 'MANUAL_REVIEW') then
            o_result := 'EXISTING';
            o_status := l_status;
        else
            update request
               set request_status = 'IN_PROGRESS',
                   started_at = coalesce(started_at, systimestamp),
                   last_updated_at = systimestamp
             where action_request_id = p_action_request_id;
            o_result := 'RESUME';
            o_status := 'IN_PROGRESS';
        end if;

        commit;
    end;

    procedure set_request_status(
        p_action_request_id in varchar2,
        p_status            in varchar2,
        p_response_payload  in clob default null
    ) is
    begin
        update request
           set request_status = p_status,
               response_payload = case when p_response_payload is not null then p_response_payload else response_payload end,
               started_at = case when p_status = 'IN_PROGRESS' then coalesce(started_at, systimestamp) else started_at end,
               completed_at = case when p_status in ('COMPLETED', 'FAILED_NO_SIDE_EFFECT', 'MANUAL_REVIEW') then systimestamp else completed_at end,
               last_updated_at = systimestamp
         where action_request_id = p_action_request_id;

        commit;
    end;

    procedure save_generated_identifier(
        p_action_request_id   in varchar2,
        p_source_system       in varchar2,
        p_source_style_ref    in varchar2,
        p_mfcs_style_no       in varchar2,
        p_source_variant_ref  in varchar2 default null,
        p_mfcs_sku_no         in varchar2 default null,
        p_sku_size            in varchar2 default null,
        p_sku_width           in varchar2 default null,
        p_source_order_ref    in varchar2 default null,
        p_mfcs_order_no       in varchar2 default null
    ) is
    begin
        update entity_map
           set mfcs_style_no = coalesce(p_mfcs_style_no, mfcs_style_no),
               mfcs_sku_no = coalesce(p_mfcs_sku_no, mfcs_sku_no),
               sku_size = coalesce(p_sku_size, sku_size),
               sku_width = coalesce(p_sku_width, sku_width),
               mfcs_order_no = coalesce(p_mfcs_order_no, mfcs_order_no),
               last_updated_at = systimestamp
         where source_system = p_source_system
           and nvl(source_style_ref, '-') = nvl(p_source_style_ref, '-')
           and nvl(source_variant_ref, '-') = nvl(p_source_variant_ref, '-')
           and nvl(source_order_ref, '-') = nvl(p_source_order_ref, '-');

        if sql%rowcount = 0 then
            insert into entity_map (
                source_system,
                source_style_ref,
                mfcs_style_no,
                source_variant_ref,
                mfcs_sku_no,
                sku_size,
                sku_width,
                source_order_ref,
                mfcs_order_no
            ) values (
                p_source_system,
                p_source_style_ref,
                p_mfcs_style_no,
                p_source_variant_ref,
                p_mfcs_sku_no,
                p_sku_size,
                p_sku_width,
                p_source_order_ref,
                p_mfcs_order_no
            );
        end if;

        update request
           set style_no = coalesce(p_mfcs_style_no, style_no),
               order_no = coalesce(p_mfcs_order_no, order_no),
               last_updated_at = systimestamp
         where action_request_id = p_action_request_id;

        commit;
    end;

    function build_status_response(
        p_action_request_id in varchar2,
        p_status_override   in varchar2 default null
    ) return clob is
        l_status varchar2(30);
        l_operation varchar2(30);
        l_style varchar2(30);
        l_order varchar2(30);
        l_failed_step varchar2(60);
        l_response clob;
        l_retryable varchar2(5);
        l_first boolean := true;
    begin
        select operation_name, request_status, style_no, order_no
          into l_operation, l_status, l_style, l_order
          from request
         where action_request_id = p_action_request_id;

        l_status := nvl(p_status_override, l_status);

        l_retryable := case when l_status in ('PARTIALLY_COMPLETED', 'OUTCOME_UNKNOWN', 'FAILED_NO_SIDE_EFFECT') then 'true' else 'false' end;
        l_response := '{'
            || '"OPERATION_NAME":"' || json_escape(l_operation) || '",'
            || '"ACTION_REQUEST_ID":"' || json_escape(p_action_request_id) || '",'
            || '"STATUS":"' || json_escape(l_status) || '",'
            || '"RETRYABLE":' || l_retryable || ','
            || '"STYLE":' || case when l_style is null then 'null' else '"' || json_escape(l_style) || '"' end || ','
            || '"ORDER_NO":' || case when l_order is null then 'null' else '"' || json_escape(l_order) || '"' end || ','
            || '"PLMSizeCurveDtl":[';

        for r in (
            select source_variant_ref, sku_size, sku_width, mfcs_sku_no
              from entity_map m
              join request r
                on r.source_system = m.source_system
               and nvl(r.source_style_ref, '-') = nvl(m.source_style_ref, '-')
             where r.action_request_id = p_action_request_id
               and m.mfcs_sku_no is not null
             order by source_variant_ref
        ) loop
            if l_first then
                l_first := false;
            else
                l_response := l_response || ',';
            end if;

            l_response := l_response
                || '{"SOURCE_VARIANT_REF":"' || json_escape(r.source_variant_ref) || '",'
                || '"SKU_SIZE":"' || json_escape(r.sku_size) || '",'
                || '"SKU_WIDTH":"' || json_escape(r.sku_width) || '",'
                || '"SKU_ID":"' || json_escape(r.mfcs_sku_no) || '"}';
        end loop;

        l_response := l_response || '],"COMPLETED_STEPS":[';
        l_first := true;
        for s in (
            select step_code
              from step
             where action_request_id = p_action_request_id
               and step_status = 'SUCCEEDED'
             order by step_sequence
        ) loop
            if l_first then
                l_first := false;
            else
                l_response := l_response || ',';
            end if;
            l_response := l_response || '"' || json_escape(s.step_code) || '"';
        end loop;

        l_response := l_response || '],"FAILED_STEP":';
        begin
            select step_code
              into l_failed_step
              from (
                  select step_code
                    from step
                   where action_request_id = p_action_request_id
                     and step_status in ('FAILED', 'OUTCOME_UNKNOWN')
                   order by step_sequence
              )
             where rownum = 1;
            l_response := l_response || '"' || json_escape(l_failed_step) || '"';
        exception
            when no_data_found then
                l_response := l_response || 'null';
        end;

        l_response := l_response || ',"GENERATED_IDENTIFIERS":{'
            || '"STYLE":' || case when l_style is null then 'null' else '"' || json_escape(l_style) || '"' end
            || ',"ORDER_NO":' || case when l_order is null then 'null' else '"' || json_escape(l_order) || '"' end
            || '},"ERRORS":[]}';

        return l_response;
    end;
end request_pkg;
/

show errors
