set define off

-- Request execution: walks the step graph, resolves each step to an MFCS
-- endpoint and method, sends the payload, and journals the outcome.
--
-- Execution is a loop over step_pkg.first_runnable_step, so resume and first
-- run are the same code path: whatever is not yet SUCCEEDED runs next. Every
-- operation sends its whole write set - see initialize_steps in step_pkg for
-- why - and the create-versus-update choice for each step is made here, in
-- endpoint_for_step, from the operation name alone.
--
-- ENSURE_STYLE_SKUS is the one step handled inline rather than through the
-- endpoint table: what it sends depends on what the tenant already holds.

prompt Creating orchestrator_pkg

create or replace package orchestrator_pkg authid definer as
    -- Runs every runnable step of a registered request, in sequence, until
    -- the graph is exhausted or a step fails. Sets the request's final status
    -- and stores the response document a duplicate submission will replay.
    procedure execute_request(
        p_action_request_id in varchar2
    );

    -- Resume is execute: the loop picks up from the first step that has not
    -- succeeded. Kept as a named entry point so the API reads honestly.
    procedure resume_request(
        p_action_request_id in varchar2
    );

    -- Pure resolvers, exposed so the preview layer can describe the planned MFCS
    -- calls without duplicating the step-to-endpoint mapping. No side effects.
    function endpoint_for_step(
        p_step_code in varchar2,
        p_operation in varchar2
    ) return varchar2;

    function method_for_step(
        p_step_code in varchar2,
        p_operation in varchar2
    ) return varchar2;

    function payload_for_step(
        p_action_request_id in varchar2,
        p_step_code         in varchar2
    ) return clob;
end orchestrator_pkg;
/

show errors

create or replace package body orchestrator_pkg as
    function request_payload(p_action_request_id in varchar2) return clob is
        l_payload clob;
    begin
        select request_payload
          into l_payload
          from request
         where action_request_id = p_action_request_id;
        return l_payload;
    end;

    function operation_name(p_action_request_id in varchar2) return varchar2 is
        l_operation varchar2(30);
    begin
        select operation_name
          into l_operation
          from request
         where action_request_id = p_action_request_id;
        return l_operation;
    end;

    function any_succeeded(p_action_request_id in varchar2) return boolean is
        l_count number;
    begin
        select count(*)
          into l_count
          from step
         where action_request_id = p_action_request_id
           and step_status = 'SUCCEEDED'
           and step_code <> 'VALIDATE_REQUEST';
        return l_count > 0;
    end;

    procedure persist_item_numbers(
        p_action_request_id in varchar2,
        p_response          in clob
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_source_system varchar2(60) := payload_pkg.source_system(l_payload);
        l_source_style_ref varchar2(120) := payload_pkg.source_style_ref(l_payload);
        l_style_no varchar2(30);
        l_sku_no varchar2(30);
        l_response_obj json_object_t;
        l_items json_array_t;
    begin
        select coalesce(
                   json_value(p_response, '$.STYLE' returning varchar2(30) null on error),
                   json_value(p_response, '$.items[0].item' returning varchar2(30) null on error)
               )
          into l_style_no
          from dual;

        request_pkg.save_generated_identifier(
            p_action_request_id => p_action_request_id,
            p_source_system => l_source_system,
            p_source_style_ref => l_source_style_ref,
            p_mfcs_style_no => l_style_no
        );

        l_response_obj := json_object_t.parse(p_response);
        if l_response_obj.has('items') then
            l_items := l_response_obj.get_array('items');
            for v in (
                select ordinality, source_variant_ref, sku_size, sku_width
                  from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                      columns
                          ordinality for ordinality,
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                          sku_size varchar2(60) path '$.SKU_SIZE',
                          sku_width varchar2(60) path '$.SKU_WIDTH'
                  )
            ) loop
                l_sku_no := treat(l_items.get(v.ordinality) as json_object_t).get_string('item');
                request_pkg.save_generated_identifier(
                    p_action_request_id => p_action_request_id,
                    p_source_system => l_source_system,
                    p_source_style_ref => l_source_style_ref,
                    p_mfcs_style_no => l_style_no,
                    p_source_variant_ref => v.source_variant_ref,
                    p_mfcs_sku_no => l_sku_no,
                    p_sku_size => v.sku_size,
                    p_sku_width => v.sku_width
                );
            end loop;
        else
            for v in (
                select source_variant_ref, sku_size, sku_width, sku_id
                  from json_table(p_response, '$.PLMSizeCurveDtl[*]'
                      columns
                          source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                          sku_size varchar2(60) path '$.SKU_SIZE',
                          sku_width varchar2(60) path '$.SKU_WIDTH',
                          sku_id varchar2(30) path '$.SKU_ID'
                  )
            ) loop
                request_pkg.save_generated_identifier(
                    p_action_request_id => p_action_request_id,
                    p_source_system => l_source_system,
                    p_source_style_ref => l_source_style_ref,
                    p_mfcs_style_no => l_style_no,
                    p_source_variant_ref => v.source_variant_ref,
                    p_mfcs_sku_no => v.sku_id,
                    p_sku_size => v.sku_size,
                    p_sku_width => v.sku_width
                );
            end loop;
        end if;
    end;

    function first_reserved_item(p_response in clob) return varchar2 is
        l_item varchar2(30);
    begin
        select coalesce(
                   json_value(p_response, '$.items[0].item' returning varchar2(30) null on error),
                   json_value(p_response, '$.item' returning varchar2(30) null on error),
                   json_value(p_response, '$.STYLE' returning varchar2(30) null on error)
               )
          into l_item
          from dual;

        if l_item is null then
            raise_application_error(-20830, 'MFCS item-number reservation response did not contain an item number.');
        end if;

        return l_item;
    end;

    procedure reserve_item_numbers_chunked(
        p_action_request_id in varchar2,
        p_user_id           in varchar2
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_source_system varchar2(60) := payload_pkg.source_system(l_payload);
        l_source_style_ref varchar2(120) := payload_pkg.source_style_ref(l_payload);
        l_request_payload clob;
        l_response clob;
        l_style_no varchar2(30);
        l_sku_no varchar2(30);
        l_days number := to_number(config_pkg.get_config('MFCS_ITEM_NUMBER_RESERVATION_DAYS_UNTIL_EXPIRY', '14'));
    begin
        l_request_payload := '{"itemNumberType":"ITEM","quantity":1,"daysUntilExpiry":' || l_days || '}';

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_CHUNK_START',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Starting chunked item-number reservation.',
            p_detail_payload => '{"sourceSystem":"' || event_pkg.escape_json(l_source_system)
                || '","sourceStyleRef":"' || event_pkg.escape_json(l_source_style_ref)
                || '","daysUntilExpiry":' || l_days || '}'
        );

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_STYLE_START',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Reserving MFCS item number for style.'
        );

        l_response := client_pkg.call_service(
            p_action_request_id => p_action_request_id,
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_http_method => 'POST',
            p_endpoint_key => 'ENDPOINT.ITEM_NUMBERS_MANAGE',
            p_request_payload => l_request_payload,
            p_user_id => p_user_id
        );

        l_style_no := first_reserved_item(l_response);

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_STYLE_SUCCEEDED',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Reserved MFCS style item number.',
            p_detail_payload => '{"mfcsStyleNo":"' || event_pkg.escape_json(l_style_no) || '"}'
        );

        request_pkg.save_generated_identifier(
            p_action_request_id => p_action_request_id,
            p_source_system => l_source_system,
            p_source_style_ref => l_source_style_ref,
            p_mfcs_style_no => l_style_no
        );

        for v in (
            select source_variant_ref, sku_size, sku_width
              from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                  columns
                      source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                      sku_size varchar2(60) path '$.SKU_SIZE',
                      sku_width varchar2(60) path '$.SKU_WIDTH'
              )
        ) loop
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'RESERVE_SKU_START',
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_message => 'Reserving MFCS item number for SKU.',
                p_detail_payload => '{"sourceVariantRef":"' || event_pkg.escape_json(v.source_variant_ref)
                    || '","skuSize":"' || event_pkg.escape_json(v.sku_size)
                    || '","skuWidth":"' || event_pkg.escape_json(v.sku_width) || '"}'
            );

            l_response := client_pkg.call_service(
                p_action_request_id => p_action_request_id,
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_http_method => 'POST',
                p_endpoint_key => 'ENDPOINT.ITEM_NUMBERS_MANAGE',
                p_request_payload => l_request_payload,
                p_user_id => p_user_id
            );

            l_sku_no := first_reserved_item(l_response);

            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'RESERVE_SKU_SUCCEEDED',
                p_step_code => 'RESERVE_ITEM_NUMBERS',
                p_message => 'Reserved MFCS SKU item number.',
                p_detail_payload => '{"sourceVariantRef":"' || event_pkg.escape_json(v.source_variant_ref)
                    || '","mfcsSkuNo":"' || event_pkg.escape_json(l_sku_no)
                    || '","mfcsStyleNo":"' || event_pkg.escape_json(l_style_no) || '"}'
            );

            request_pkg.save_generated_identifier(
                p_action_request_id => p_action_request_id,
                p_source_system => l_source_system,
                p_source_style_ref => l_source_style_ref,
                p_mfcs_style_no => l_style_no,
                p_source_variant_ref => v.source_variant_ref,
                p_mfcs_sku_no => l_sku_no,
                p_sku_size => v.sku_size,
                p_sku_width => v.sku_width
            );
        end loop;

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'RESERVE_CHUNK_COMPLETE',
            p_step_code => 'RESERVE_ITEM_NUMBERS',
            p_message => 'Chunked item-number reservation completed.',
            p_detail_payload => '{"mfcsStyleNo":"' || event_pkg.escape_json(l_style_no) || '"}'
        );
    end;

    procedure persist_po_number(
        p_action_request_id in varchar2,
        p_response          in clob
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_order_no varchar2(30);
    begin
        select coalesce(
                   json_value(p_response, '$.ORDER_NO' returning varchar2(30) null on error),
                   json_value(p_response, '$.orderNumbers[0].orderNo' returning varchar2(30) null on error)
               )
          into l_order_no
          from dual;

        request_pkg.save_generated_identifier(
            p_action_request_id => p_action_request_id,
            p_source_system => payload_pkg.source_system(l_payload),
            p_source_style_ref => payload_pkg.source_style_ref(l_payload),
            p_mfcs_style_no => null,
            p_source_order_ref => payload_pkg.source_order_ref(l_payload),
            p_mfcs_order_no => l_order_no
        );
    end;

    function payload_for_step(
        p_action_request_id in varchar2,
        p_step_code in varchar2
    ) return clob is
    begin
        case p_step_code
            when 'RESERVE_ITEM_NUMBERS' then return payload_pkg.build_request(p_action_request_id, 'build_item_number_request');
            when 'CREATE_PARENT_ITEM_HIERARCHY' then return payload_pkg.build_request(p_action_request_id, 'build_parent_item_create_request');
            when 'CREATE_CHILD_ITEM_HIERARCHY' then return payload_pkg.build_request(p_action_request_id, 'build_child_item_create_request');
            when 'CREATE_ITEM_HIERARCHY' then return payload_pkg.build_request(p_action_request_id, 'build_item_create_request');
            when 'CREATE_PARENT_ITEM_SOURCING' then return payload_pkg.build_request(p_action_request_id, 'build_parent_item_sourcing_request');
            when 'CREATE_ITEM_SOURCING' then return payload_pkg.build_request(p_action_request_id, 'build_item_sourcing_request');
            when 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' then return payload_pkg.build_request(p_action_request_id, 'build_item_country_of_manufacture_request');
            when 'CREATE_ITEM_UDAS' then return payload_pkg.build_request(p_action_request_id, 'build_item_uda_request');
            when 'CREATE_ITEM_LOCATIONS' then return payload_pkg.build_request(p_action_request_id, 'build_item_location_request');
            when 'APPROVE_ITEMS' then return payload_pkg.build_request(p_action_request_id, 'build_item_approval_request');
            when 'APPLY_INITIAL_RETAIL' then return payload_pkg.build_request(p_action_request_id, 'build_initial_retail_request');
            when 'RESERVE_ORDER_NUMBER' then return payload_pkg.build_request(p_action_request_id, 'build_po_number_request');
            when 'CREATE_PURCHASE_ORDER' then return payload_pkg.build_request(p_action_request_id, 'build_purchase_order_request');
            when 'VERIFY_PURCHASE_ORDER' then return payload_pkg.build_request(p_action_request_id, 'build_purchase_order_verify_request');
            else return '{"step":"' || p_step_code || '"}';
        end case;
    end;

    -- Whether the operation writes to a style that already exists in MFCS.
    --
    -- Order operations belong here as much as MODIFY_STYLE does: they carry the full
    -- style write set, so their item steps have to resolve to the update services.
    -- CREATE_ALL does not, because it creates the style in the same request.
    function targets_existing_style(p_operation in varchar2) return boolean is
    begin
        return p_operation in ('MODIFY_STYLE', 'CREATE_ORDER', 'MODIFY_ORDER');
    end;

    function endpoint_for_step(p_step_code in varchar2, p_operation in varchar2) return varchar2 is
    begin
        case p_step_code
            when 'ENSURE_STYLE_SKUS' then return null;
            when 'RESERVE_ITEM_NUMBERS' then return 'ENDPOINT.ITEM_NUMBERS_MANAGE';
            when 'CREATE_PARENT_ITEM_HIERARCHY' then return 'ENDPOINT.ITEMS_CREATE';
            when 'CREATE_CHILD_ITEM_HIERARCHY' then return 'ENDPOINT.ITEMS_CREATE';
            when 'CREATE_ITEM_HIERARCHY' then
                if targets_existing_style(p_operation) then
                    return 'ENDPOINT.ITEMS_UPDATE';
                end if;
                return 'ENDPOINT.ITEMS_CREATE';
            when 'CREATE_PARENT_ITEM_SOURCING' then return 'ENDPOINT.ITEM_SOURCING_CREATE';
            when 'CREATE_ITEM_SOURCING' then
                if targets_existing_style(p_operation) then return 'ENDPOINT.ITEM_SOURCING_UPDATE'; end if;
                return 'ENDPOINT.ITEM_SOURCING_CREATE';
            when 'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE' then
                -- Re-creating one is not a no-op, it is an error: "This
                -- item/supplier/manufacturing country already exists ...
                -- CORESVC_ITEM.PROCESS_ISMC". The update service takes the same body.
                if targets_existing_style(p_operation) then
                    return 'ENDPOINT.ITEM_COUNTRIES_OF_MANUFACTURE_UPDATE';
                end if;
                return 'ENDPOINT.ITEM_COUNTRIES_OF_MANUFACTURE_CREATE';
            when 'CREATE_ITEM_UDAS' then
                if targets_existing_style(p_operation) then return 'ENDPOINT.ITEM_UDAS_UPDATE'; end if;
                return 'ENDPOINT.ITEM_UDAS_CREATE';
            when 'CREATE_ITEM_LOCATIONS' then
                if targets_existing_style(p_operation) then return 'ENDPOINT.ITEM_LOCATIONS_UPDATE'; end if;
                return 'ENDPOINT.ITEM_LOCATIONS_CREATE';
            when 'APPROVE_ITEMS' then return 'ENDPOINT.ITEM_APPROVE';
            when 'APPLY_INITIAL_RETAIL' then return 'ENDPOINT.INITIAL_RETAIL';
            when 'RESERVE_ORDER_NUMBER' then return 'ENDPOINT.PO_PREISSUED_CREATE';
            when 'CREATE_PURCHASE_ORDER' then
                if p_operation = 'MODIFY_ORDER' then return 'ENDPOINT.PURCHASE_ORDERS_UPDATE'; end if;
                return 'ENDPOINT.PURCHASE_ORDERS_CREATE';
            when 'VERIFY_PURCHASE_ORDER' then return 'ENDPOINT.PURCHASE_ORDER_GET';
            else return null;
        end case;
    end;

    function method_for_step(p_step_code in varchar2, p_operation in varchar2) return varchar2 is
    begin
        if p_step_code = 'VERIFY_PURCHASE_ORDER' then
            return 'GET';
        elsif p_step_code = 'APPROVE_ITEMS' then
            return 'PUT';
        elsif targets_existing_style(p_operation)
              and p_step_code in ('CREATE_ITEM_HIERARCHY', 'CREATE_ITEM_SOURCING',
                                  'CREATE_ITEM_COUNTRIES_OF_MANUFACTURE', 'CREATE_ITEM_UDAS',
                                  'CREATE_ITEM_LOCATIONS', 'APPROVE_ITEMS') then
            return 'PUT';
        elsif p_step_code = 'CREATE_PURCHASE_ORDER' and p_operation = 'MODIFY_ORDER' then
            return 'PUT';
        end if;
        return 'POST';
    end;

    -- json_object_t.get_boolean returns NULL for an absent key, and NULL in a PL/SQL
    -- condition is not false - "if not x" simply does nothing. Every branch below
    -- turns on one of these, so the absent case is made explicit.
    function is_true(p_value in boolean) return boolean is
    begin
        return p_value is not null and p_value;
    end;

    -- Records the SKU behind every colour/size combination the request names, as the
    -- tenant currently reports it.
    --
    -- The order builders resolve a SKU through entity_map when the document does not
    -- carry one, and a style created by an earlier request - or by somebody else
    -- entirely - leaves no row behind. Reading the mapping out of the gap analysis
    -- costs nothing extra: it has just been fetched.
    procedure record_resolved_skus(
        p_action_request_id in varchar2,
        p_style             in varchar2,
        p_gap               in json_object_t
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_source_system varchar2(60) := payload_pkg.source_system(l_payload);
        l_source_style_ref varchar2(120) := payload_pkg.source_style_ref(l_payload);
        l_required json_array_t := p_gap.get_array('required');
        l_entry json_object_t;
        l_size varchar2(60);
        l_sku varchar2(30);
        l_source_variant_ref varchar2(120);
        l_sku_width varchar2(60);
        l_recorded pls_integer := 0;
    begin
        if l_required is null then
            return;
        end if;

        for i in 0 .. l_required.get_size - 1 loop
            l_entry := treat(l_required.get(i) as json_object_t);
            l_sku := l_entry.get_string('sku');
            l_size := l_entry.get_string('size');

            if l_sku is not null then
                -- Join back to the size-curve row so the SKU is filed under the same
                -- source reference the rest of the request uses. Width is not part of
                -- the diff pair, so a size that appears twice with different widths
                -- resolves to the same SKU; take the first and let the mapping stand.
                begin
                    select source_variant_ref, sku_width
                      into l_source_variant_ref, l_sku_width
                      from (
                          select source_variant_ref, sku_width
                            from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                                columns
                                    source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                                    sku_size varchar2(60) path '$.SKU_SIZE',
                                    sku_width varchar2(60) path '$.SKU_WIDTH'
                            )
                           where sku_size = l_size
                      )
                     where rownum = 1;
                exception
                    when no_data_found then
                        l_source_variant_ref := null;
                        l_sku_width := null;
                end;

                if l_source_variant_ref is not null then
                    request_pkg.save_generated_identifier(
                        p_action_request_id => p_action_request_id,
                        p_source_system => l_source_system,
                        p_source_style_ref => l_source_style_ref,
                        p_mfcs_style_no => p_style,
                        p_source_variant_ref => l_source_variant_ref,
                        p_mfcs_sku_no => l_sku,
                        p_sku_size => l_size,
                        p_sku_width => l_sku_width
                    );
                    l_recorded := l_recorded + 1;
                end if;
            end if;
        end loop;

        if l_recorded > 0 then
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'SKU_MAPPING_RECORDED',
                p_step_code => 'ENSURE_STYLE_SKUS',
                p_message => 'Recorded the SKU behind each requested combination.',
                p_detail_payload => '{"mfcsStyleNo":"' || event_pkg.escape_json(p_style)
                    || '","skuCount":' || l_recorded || '}'
            );
        end if;
    end;

    -- Creates the children a style is missing: reserve a number for each, create
    -- them under the parent, give them sourcing and a country of manufacture, and
    -- approve them.
    --
    -- The order is not negotiable. MFCS will not approve an item that has no
    -- sourcing, and it will not accept sourcing for an item that does not exist yet.
    procedure generate_missing_skus(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_style             in varchar2,
        p_colour            in varchar2,
        p_sizes             in varchar2,
        p_gap               in json_object_t,
        p_user_id           in varchar2
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_attrs json_object_t := json_object_t.parse(sku_pkg.style_attributes(p_style));
        l_missing json_array_t := p_gap.get_array('missing');
        l_entry json_object_t;
        l_child json_object_t;
        l_children json_array_t := json_array_t();
        l_plan json_object_t := json_object_t();
        l_plan_clob clob;
        l_unmapped varchar2(1000);
        l_created varchar2(2000);
        l_response clob;
        l_item varchar2(30);
        l_size varchar2(60);
        l_source_variant_ref varchar2(120);
        l_sku_width varchar2(60);
        l_days number :=
            to_number(config_pkg.get_config('MFCS_ITEM_NUMBER_RESERVATION_DAYS_UNTIL_EXPIRY', '14'));
        l_retries number :=
            to_number(config_pkg.get_config('MFCS_SKU_VERIFY_RETRY_COUNT', '6'));
        l_sleep number :=
            to_number(config_pkg.get_config('MFCS_SKU_VERIFY_RETRY_SLEEP_SECONDS', '5'));
        l_verify json_object_t;
        l_verified boolean := false;
    begin
        -- A child has to join its parent's merchandise hierarchy. Nothing in this
        -- layer is entitled to guess one, so an unreadable parent stops the work
        -- before any item number is burned.
        if not is_true(l_attrs.get_boolean('available')) then
            raise_application_error(-20962,
                'Cannot create children for style ' || p_style || ': its own attributes '
                || 'could not be read (' || l_attrs.get_string('message')
                || '). A child inherits the parent hierarchy, so it cannot be guessed.');
        end if;

        for i in 0 .. l_missing.get_size - 1 loop
            l_entry := treat(l_missing.get(i) as json_object_t);
            if not is_true(l_entry.get_boolean('mappingFound')) then
                l_unmapped := l_unmapped
                    || case when l_unmapped is not null then ', ' end
                    || l_entry.get_string('size');
            end if;
        end loop;

        -- An unmapped size would go out as a null differentiator. The gap analysis
        -- reads diffs back through the same MAP.SIZE entries, so even if MFCS took
        -- it, the next run would report the same combination missing again.
        if l_unmapped is not null then
            raise_application_error(-20963,
                'Style ' || p_style || ' needs sizes that have no MAP.SIZE mapping: '
                || substr(l_unmapped, 1, 300) || '. Add the mapping before creating children.');
        end if;

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'SKU_GENERATION_START',
            p_step_code => p_step_code,
            p_message => 'Creating the children this style is missing.',
            p_detail_payload => '{"mfcsStyleNo":"' || event_pkg.escape_json(p_style)
                || '","colour":"' || event_pkg.escape_json(p_colour)
                || '","missingCount":' || l_missing.get_size || '}'
        );

        -- One reservation per child, matching how the create flow reserves numbers.
        for i in 0 .. l_missing.get_size - 1 loop
            l_entry := treat(l_missing.get(i) as json_object_t);
            l_size := l_entry.get_string('size');

            begin
                select source_variant_ref, sku_width
                  into l_source_variant_ref, l_sku_width
                  from (
                      select source_variant_ref, sku_width
                        from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
                            columns
                                source_variant_ref varchar2(120) path '$.SOURCE_VARIANT_REF',
                                sku_size varchar2(60) path '$.SKU_SIZE',
                                sku_width varchar2(60) path '$.SKU_WIDTH'
                        )
                       where sku_size = l_size
                  )
                 where rownum = 1;
            exception
                when no_data_found then
                    l_source_variant_ref := null;
                    l_sku_width := null;
            end;

            l_response := client_pkg.call_service(
                p_action_request_id => p_action_request_id,
                p_step_code => p_step_code,
                p_http_method => 'POST',
                p_endpoint_key => 'ENDPOINT.ITEM_NUMBERS_MANAGE',
                p_request_payload =>
                    '{"itemNumberType":"ITEM","quantity":1,"daysUntilExpiry":' || l_days || '}',
                p_user_id => p_user_id
            );
            l_item := first_reserved_item(l_response);

            l_child := json_object_t();
            l_child.put('item', l_item);
            l_child.put('size', l_size);
            l_child.put('sizeDiff', l_entry.get_string('sizeDiff'));
            l_child.put('colourDiff', l_entry.get_string('colourDiff'));
            if l_source_variant_ref is not null then
                l_child.put('sourceVariantRef', l_source_variant_ref);
            end if;
            if l_sku_width is not null then
                l_child.put('skuWidth', l_sku_width);
            end if;
            l_children.append(l_child);

            l_created := l_created
                || case when l_created is not null then ', ' end
                || l_item || ' (' || l_entry.get_string('colourDiff')
                || '/' || l_entry.get_string('sizeDiff') || ')';

            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'SKU_NUMBER_RESERVED',
                p_step_code => p_step_code,
                p_message => 'Reserved an item number for a missing combination.',
                p_detail_payload => '{"mfcsSkuNo":"' || event_pkg.escape_json(l_item)
                    || '","size":"' || event_pkg.escape_json(l_size)
                    || '","sizeDiff":"' || event_pkg.escape_json(l_entry.get_string('sizeDiff'))
                    || '","colourDiff":"' || event_pkg.escape_json(l_entry.get_string('colourDiff')) || '"}'
            );
        end loop;

        l_plan.put('style', p_style);
        l_plan.put('attributes', l_attrs);
        l_plan.put('children', l_children);
        l_plan_clob := l_plan.to_clob;

        l_response := client_pkg.call_service(
            p_action_request_id => p_action_request_id,
            p_step_code => p_step_code,
            p_http_method => 'POST',
            p_endpoint_key => 'ENDPOINT.ITEMS_CREATE',
            p_request_payload => payload_pkg.generated_child_create_request(p_action_request_id, l_plan_clob),
            p_user_id => p_user_id
        );

        l_response := client_pkg.call_service(
            p_action_request_id => p_action_request_id,
            p_step_code => p_step_code,
            p_http_method => 'POST',
            p_endpoint_key => 'ENDPOINT.ITEM_SOURCING_CREATE',
            p_request_payload => payload_pkg.generated_child_sourcing_request(p_action_request_id, l_plan_clob),
            p_user_id => p_user_id
        );

        l_response := client_pkg.call_service(
            p_action_request_id => p_action_request_id,
            p_step_code => p_step_code,
            p_http_method => 'POST',
            p_endpoint_key => 'ENDPOINT.ITEM_COUNTRIES_OF_MANUFACTURE_CREATE',
            p_request_payload => payload_pkg.generated_child_com_request(p_action_request_id, l_plan_clob),
            p_user_id => p_user_id
        );

        l_response := client_pkg.call_service(
            p_action_request_id => p_action_request_id,
            p_step_code => p_step_code,
            p_http_method => 'PUT',
            p_endpoint_key => 'ENDPOINT.ITEM_APPROVE',
            p_request_payload => payload_pkg.generated_child_approval_request(p_action_request_id, l_plan_clob),
            p_user_id => p_user_id
        );

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'SKU_GENERATION_SENT',
            p_step_code => p_step_code,
            p_message => 'Created, sourced and approved the missing children.',
            p_detail_payload => '{"mfcsStyleNo":"' || event_pkg.escape_json(p_style)
                || '","children":"' || event_pkg.escape_json(substr(l_created, 1, 900)) || '"}'
        );

        -- Read the style back rather than trusting four HTTP 200s. This is the whole
        -- reason the step exists: MFCS answers an item write that changes nothing
        -- with SUCCESS, so the only evidence that the children now exist is finding
        -- them. Newly approved items take a moment to become readable, hence retries.
        for i in 1 .. greatest(1, l_retries) loop
            l_verify := json_object_t.parse(sku_pkg.resolve_gap(p_style, p_colour, p_sizes));
            l_verified := is_true(l_verify.get_boolean('resolved'))
                          and is_true(l_verify.get_boolean('complete'));
            exit when l_verified;

            if i < greatest(1, l_retries) then
                event_pkg.log_event(
                    p_action_request_id => p_action_request_id,
                    p_event_phase => 'SKU_VERIFY_RETRY_WAIT',
                    p_step_code => p_step_code,
                    p_event_level => 'WARN',
                    p_message => 'The new children are not readable yet; waiting before re-reading.',
                    p_detail_payload => '{"retryNumber":' || i
                        || ',"maxRetries":' || greatest(1, l_retries)
                        || ',"sleepSeconds":' || l_sleep || '}'
                );
                dbms_session.sleep(l_sleep);
            end if;
        end loop;

        if not l_verified then
            raise_application_error(-20965,
                'Created children for style ' || p_style || ' but reading the style back still '
                || 'reports ' || nvl(to_char(l_verify.get_number('missingCount')), 'some')
                || ' combination(s) missing. MFCS accepted the calls without applying them.');
        end if;

        record_resolved_skus(p_action_request_id, p_style, l_verify);

        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'SKU_GENERATION_VERIFIED',
            p_step_code => p_step_code,
            p_message => 'Style ' || p_style || ' now carries every requested combination.',
            p_detail_payload => '{"mfcsStyleNo":"' || event_pkg.escape_json(p_style)
                || '","createdCount":' || l_children.get_size || '}'
        );
    end;

    -- Confirms the style carries every colour/size combination the request names,
    -- and creates the ones it does not.
    --
    -- Why this is one step rather than five: which children are missing is only
    -- known after reading the tenant, so a step graph fixed at request registration
    -- cannot express it. Doing the work inline also makes the step re-entrant for
    -- nothing - a resume re-reads the style, sees whatever a failed attempt managed
    -- to create, and creates only the remainder. Stored-payload steps could not,
    -- because they would replay item numbers that had already been used.
    --
    -- With generation switched off the step still runs, and still stops the request.
    -- That is deliberate: MFCS accepts a diff change on an existing SKU, reports
    -- SUCCESS and leaves the item alone, so an unchecked colour change would
    -- complete having achieved nothing at all.
    procedure ensure_style_skus(
        p_action_request_id in varchar2,
        p_step_code         in varchar2,
        p_user_id           in varchar2
    ) is
        l_payload clob := request_payload(p_action_request_id);
        l_style varchar2(30);
        l_colour varchar2(120);
        l_sizes varchar2(4000);
        l_gap json_object_t;
        l_missing json_array_t;
        l_entry json_object_t;
        l_detail varchar2(2000);
        l_generate boolean :=
            config_pkg.get_config('FEATURE_GENERATE_MISSING_SKUS_YN', 'Y') = 'Y';
    begin
        select style_no into l_style
          from request where action_request_id = p_action_request_id;

        l_colour := payload_pkg.string_value(l_payload, 'COLOUR');

        select listagg(sku_size, ':') within group (order by rn)
          into l_sizes
          from json_table(l_payload, '$.PLMSizeCurveDtl[*]'
              columns rn for ordinality, sku_size varchar2(40) path '$.SKU_SIZE');

        if l_style is null then
            step_pkg.set_step_status(p_action_request_id, p_step_code, 'SUCCEEDED');
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'ENSURE_SKUS_SKIPPED',
                p_step_code => p_step_code,
                p_message => 'No style on the request to check against.');
            return;
        end if;

        l_gap := json_object_t.parse(sku_pkg.resolve_gap(l_style, l_colour, l_sizes));

        if not is_true(l_gap.get_boolean('resolved')) then
            step_pkg.set_step_status(p_action_request_id, p_step_code, 'FAILED',
                'SKU_LOOKUP_FAILED', substr(l_gap.get_string('message'), 1, 400));
            raise_application_error(-20960,
                'Could not read the SKUs of style ' || l_style || ': ' || l_gap.get_string('message'));
        end if;

        if is_true(l_gap.get_boolean('complete')) then
            record_resolved_skus(p_action_request_id, l_style, l_gap);
            step_pkg.set_step_status(p_action_request_id, p_step_code, 'SUCCEEDED');
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'ENSURE_SKUS_COMPLETE',
                p_step_code => p_step_code,
                p_message => 'Style ' || l_style || ' already carries every requested combination.');
            return;
        end if;

        if l_generate then
            generate_missing_skus(
                p_action_request_id => p_action_request_id,
                p_step_code => p_step_code,
                p_style => l_style,
                p_colour => l_colour,
                p_sizes => l_sizes,
                p_gap => l_gap,
                p_user_id => p_user_id
            );
            step_pkg.set_step_status(p_action_request_id, p_step_code, 'SUCCEEDED');
            return;
        end if;

        l_missing := l_gap.get_array('missing');
        for i in 0 .. l_missing.get_size - 1 loop
            l_entry := treat(l_missing.get(i) as json_object_t);
            l_detail := l_detail
                || case when l_detail is not null then ', ' end
                || l_gap.get_string('colourDiff') || '/'
                || nvl(l_entry.get_string('sizeDiff'),
                       '(unmapped size ' || l_entry.get_string('size') || ')');
        end loop;

        step_pkg.set_step_status(p_action_request_id, p_step_code, 'FAILED', 'SKUS_MISSING',
            substr('Style ' || l_style || ' has no SKU for: ' || l_detail
                || '. A colour or size the style does not already carry needs new child items, '
                || 'and FEATURE_GENERATE_MISSING_SKUS_YN is off.',
                1, 1000));
        raise_application_error(-20961,
            'Style ' || l_style || ' is missing ' || l_gap.get_number('missingCount')
            || ' SKU(s): ' || substr(l_detail, 1, 300));
    end;

    procedure execute_request(
        p_action_request_id in varchar2
    ) is
        l_step varchar2(60);
        l_operation varchar2(30) := operation_name(p_action_request_id);
        l_payload clob := request_payload(p_action_request_id);
        l_user_id varchar2(120) := payload_pkg.user_id(l_payload);
        l_request_payload clob;
        l_response clob;
        l_endpoint_key varchar2(200);
        l_method varchar2(10);
        l_recovery_status varchar2(30);
        l_started_at timestamp with time zone := systimestamp;
        l_budget_seconds number := to_number(config_pkg.get_config('INTERNAL_TIME_BUDGET_SECONDS', '240'));
        l_verify_retry_count number := to_number(config_pkg.get_config('MFCS_ORDER_VERIFY_RETRY_COUNT', '12'));
        l_verify_retry_sleep number := to_number(config_pkg.get_config('MFCS_ORDER_VERIFY_RETRY_SLEEP_SECONDS', '10'));
    begin
        if l_operation = 'CREATE_ALL'
           and config_pkg.get_config('BATCH_WINDOW_ACTIVE_YN', 'N') = 'Y'
           and not any_succeeded(p_action_request_id) then
            request_pkg.set_request_status(
                p_action_request_id,
                'FAILED_NO_SIDE_EFFECT',
                '{"ACTION_REQUEST_ID":"' || p_action_request_id || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":true,"COMPLETED_STEPS":[],"FAILED_STEP":null,"GENERATED_IDENTIFIERS":{},"ERRORS":[{"FIELD":"MFCS_BATCH_WINDOW","CODE":"MFCS_BATCH_WINDOW_ACTIVE","MESSAGE":"Required MFCS services are unavailable during the configured batch window."}]}'
            );
            return;
        end if;

        request_pkg.set_request_status(p_action_request_id, 'IN_PROGRESS');
        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'REQUEST_EXECUTE_START',
            p_message => 'MFCS orchestration started.',
            p_detail_payload => '{"operationName":"' || event_pkg.escape_json(l_operation)
                || '","userId":"' || event_pkg.escape_json(l_user_id)
                || '","budgetSeconds":' || l_budget_seconds || '}'
        );
        step_pkg.set_step_status(p_action_request_id, 'VALIDATE_REQUEST', 'SUCCEEDED');

        loop
            l_step := step_pkg.first_runnable_step(p_action_request_id);
            exit when l_step is null;

            if l_step = 'VALIDATE_REQUEST' then
                step_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
                continue;
            end if;

            if l_step = 'ENSURE_STYLE_SKUS' then
                ensure_style_skus(p_action_request_id, l_step, l_user_id);
                continue;
            end if;

            if (cast(systimestamp as date) - cast(l_started_at as date)) * 86400 >= l_budget_seconds then
                request_pkg.set_request_status(
                    p_action_request_id,
                    case when any_succeeded(p_action_request_id) then 'PARTIALLY_COMPLETED' else 'FAILED_NO_SIDE_EFFECT' end,
                    request_pkg.build_status_response(
                        p_action_request_id,
                        case when any_succeeded(p_action_request_id) then 'PARTIALLY_COMPLETED' else 'FAILED_NO_SIDE_EFFECT' end
                    )
                );
                return;
            end if;

            select step_status
              into l_recovery_status
              from step
             where action_request_id = p_action_request_id
               and step_code = l_step;

            if l_recovery_status = 'OUTCOME_UNKNOWN' then
                l_recovery_status := recovery_pkg.resolve_step(p_action_request_id, l_step);
                if l_recovery_status = 'SUCCEEDED' then
                    continue;
                elsif l_recovery_status = 'MANUAL_REVIEW' then
                    return;
                end if;
            end if;

            l_endpoint_key := endpoint_for_step(l_step, l_operation);
            l_method := method_for_step(l_step, l_operation);
            l_request_payload := payload_for_step(p_action_request_id, l_step);

            step_pkg.set_step_status(p_action_request_id, l_step, 'IN_PROGRESS');
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_START',
                p_step_code => l_step,
                p_message => 'MFCS orchestration step started.',
                p_detail_payload => '{"endpointKey":"' || event_pkg.escape_json(l_endpoint_key)
                    || '","method":"' || event_pkg.escape_json(l_method)
                    || '","requestBytes":' || coalesce(to_char(dbms_lob.getlength(l_request_payload)), '0') || '}'
            );

            if l_step = 'RESERVE_ITEM_NUMBERS'
               and to_number(config_pkg.get_config('MFCS_ITEM_NUMBER_RESERVATION_CHUNK_SIZE', '1')) = 1 then
                reserve_item_numbers_chunked(p_action_request_id, l_user_id);
                step_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
                event_pkg.log_event(
                    p_action_request_id => p_action_request_id,
                    p_event_phase => 'STEP_SUCCEEDED',
                    p_step_code => l_step,
                    p_message => 'MFCS orchestration step succeeded.'
                );
                continue;
            end if;

            if l_step = 'VERIFY_PURCHASE_ORDER' then
                for i in 1 .. greatest(1, l_verify_retry_count) loop
                    begin
                        l_response := client_pkg.call_service(
                            p_action_request_id => p_action_request_id,
                            p_step_code => l_step,
                            p_http_method => l_method,
                            p_endpoint_key => l_endpoint_key,
                            p_request_payload => l_request_payload,
                            p_user_id => l_user_id
                        );
                        exit;
                    exception
                        when client_pkg.e_downstream_failure then
                            if i >= greatest(1, l_verify_retry_count) then
                                raise;
                            end if;
                            event_pkg.log_event(
                                p_action_request_id => p_action_request_id,
                                p_event_phase => 'VERIFY_RETRY_WAIT',
                                p_step_code => l_step,
                                p_event_level => 'WARN',
                                p_message => 'Purchase order verification failed; waiting before retry.',
                                p_detail_payload => '{"retryNumber":' || i
                                    || ',"maxRetries":' || greatest(1, l_verify_retry_count)
                                    || ',"sleepSeconds":' || l_verify_retry_sleep || '}'
                            );
                            dbms_session.sleep(l_verify_retry_sleep);
                    end;
                end loop;
            else
                l_response := client_pkg.call_service(
                    p_action_request_id => p_action_request_id,
                    p_step_code => l_step,
                    p_http_method => l_method,
                    p_endpoint_key => l_endpoint_key,
                    p_request_payload => l_request_payload,
                    p_user_id => l_user_id
                );
            end if;

            if l_step = 'RESERVE_ITEM_NUMBERS' then
                persist_item_numbers(p_action_request_id, l_response);
            elsif l_step = 'RESERVE_ORDER_NUMBER' then
                persist_po_number(p_action_request_id, l_response);
            end if;

            step_pkg.set_step_status(p_action_request_id, l_step, 'SUCCEEDED');
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_SUCCEEDED',
                p_step_code => l_step,
                p_message => 'MFCS orchestration step succeeded.'
            );
        end loop;

        request_pkg.set_request_status(
            p_action_request_id,
            'COMPLETED',
            request_pkg.build_status_response(p_action_request_id, 'COMPLETED')
        );
        event_pkg.log_event(
            p_action_request_id => p_action_request_id,
            p_event_phase => 'REQUEST_COMPLETED',
            p_message => 'MFCS orchestration completed.'
        );
    exception
        when client_pkg.e_outcome_unknown then
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_OUTCOME_UNKNOWN',
                p_step_code => l_step,
                p_event_level => 'WARN',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode || '}'
            );
            step_pkg.set_step_status(p_action_request_id, l_step, 'OUTCOME_UNKNOWN', null, 'OUTCOME_UNKNOWN', sqlerrm);
            request_pkg.set_request_status(p_action_request_id, 'OUTCOME_UNKNOWN', request_pkg.build_status_response(p_action_request_id, 'OUTCOME_UNKNOWN'));
        when others then
            event_pkg.log_event(
                p_action_request_id => p_action_request_id,
                p_event_phase => 'STEP_EXCEPTION',
                p_step_code => l_step,
                p_event_level => 'ERROR',
                p_message => substr(sqlerrm, 1, 1000),
                p_detail_payload => '{"sqlcode":' || sqlcode || '}'
            );
            if l_step is not null then
                step_pkg.set_step_status(p_action_request_id, l_step, 'FAILED', null, to_char(sqlcode), sqlerrm);
            end if;

            if any_succeeded(p_action_request_id) then
                request_pkg.set_request_status(p_action_request_id, 'PARTIALLY_COMPLETED', request_pkg.build_status_response(p_action_request_id, 'PARTIALLY_COMPLETED'));
            else
                request_pkg.set_request_status(
                    p_action_request_id,
                    'FAILED_NO_SIDE_EFFECT',
                    '{"ACTION_REQUEST_ID":"' || p_action_request_id || '","STATUS":"FAILED_NO_SIDE_EFFECT","RETRYABLE":true,"COMPLETED_STEPS":[],"FAILED_STEP":"' || l_step || '","GENERATED_IDENTIFIERS":{},"ERRORS":[{"FIELD":"' || l_step || '","CODE":"' || sqlcode || '","MESSAGE":"' || replace(sqlerrm, '"', '\"') || '"}]}'
                );
            end if;
    end;

    procedure resume_request(
        p_action_request_id in varchar2
    ) is
    begin
        execute_request(p_action_request_id);
    end;
end orchestrator_pkg;
/

show errors
