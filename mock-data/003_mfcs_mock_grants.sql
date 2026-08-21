set define off

prompt Granting MFCS mock-data access to MFCS_INTEGRATION

grant select, insert, update, delete on mfcs_api_capture to MFCS_INTEGRATION;
grant select, insert, update, delete on mfcs_foundation_item to MFCS_INTEGRATION;
grant select, insert, update, delete on mfcs_foundation_supplier to MFCS_INTEGRATION;
grant select, insert, update, delete on mfcs_foundation_supplier_country to MFCS_INTEGRATION;
grant select on mfcs_api_capture_seq to MFCS_INTEGRATION;

prompt MFCS mock-data grants created
