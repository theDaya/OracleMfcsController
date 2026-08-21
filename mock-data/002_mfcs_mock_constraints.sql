set define off

prompt Creating MFCS mock-data constraints

alter table mfcs_api_capture add constraint mfcs_api_capture_pk
    primary key (capture_id);

alter table mfcs_api_capture add constraint mfcs_api_capture_json_ck
    check (response_payload is json);

alter table mfcs_foundation_item add constraint mfcs_foundation_item_pk
    primary key (item);

alter table mfcs_foundation_item add constraint mfcs_found_item_capture_fk
    foreign key (source_capture_id)
    references mfcs_api_capture (capture_id);

alter table mfcs_foundation_supplier add constraint mfcs_found_supplier_pk
    primary key (item, supplier);

alter table mfcs_foundation_supplier add constraint mfcs_found_supplier_item_fk
    foreign key (item)
    references mfcs_foundation_item (item);

alter table mfcs_foundation_supplier add constraint mfcs_found_supplier_cap_fk
    foreign key (source_capture_id)
    references mfcs_api_capture (capture_id);

alter table mfcs_foundation_supplier_country add constraint mfcs_found_supp_country_pk
    primary key (item, supplier, origin_country_id);

alter table mfcs_foundation_supplier_country add constraint mfcs_found_supp_country_supp_fk
    foreign key (item, supplier)
    references mfcs_foundation_supplier (item, supplier);

alter table mfcs_foundation_supplier_country add constraint mfcs_found_supp_country_cap_fk
    foreign key (source_capture_id)
    references mfcs_api_capture (capture_id);

create index mfcs_api_capture_resource_ix
    on mfcs_api_capture (resource_type, resource_key, captured_at);

create index mfcs_foundation_item_dept_ix
    on mfcs_foundation_item (dept, class, subclass);

prompt MFCS mock-data constraints created
