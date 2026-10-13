-- Builds the full call plan for one document without sending any of it, and
-- writes nothing that survives: preview registers a throwaway request and
-- removes it. Run once 06 shows the refresh finished, in APEX: SQL Workshop > SQL Scripts.
--
-- The document is the last style created on STG before this move (request
-- CLAUDE-RETAIL-CH-20260928091040260 on mdutils), with its references renamed.
--
-- What to expect: HTTP 200 and 14 calls, from VALIDATE_REQUEST to
-- CREATE_REFERENCE_ITEMS - the same plan this document produced on mdutils.
--
-- An error naming DEPARTMENT, CLASS or SUBCLASS means the hierarchy did not load
-- from RDS. One naming SUPPLIER means the supplier feed did not load.
--
-- COLOUR 08610 is accepted, and should not be. It is a supplier colour (diff
-- type SC), retired when STG was restructured, but the item feed still reports
-- items carrying it as a colour, and the harvest records it as one. That is a
-- known defect of the master data cache, not of the move, and is fixed when the
-- cache moves onto the RDS views.

-- A plain table, not a global temporary one: a temporary table that holds
-- rows cannot be dropped by the session that wrote them.
create table ie_mfcs_stg_preview_check (
    http_status number,
    response    clob
);

declare
    l_status number;
    l_response clob;
begin
    ie_mfcs_preview.preview_transaction(q'~{
        "ACTION_REQUEST_ID": "RDS-PREVIEW-CHECK",
        "OPERATION_NAME": "CREATE_STYLE",
        "SOURCE_SYSTEM": "OFFICE_DEV",
        "SOURCE_STYLE_REF": "RDS preview check",
        "SOURCE_VERSION": "1",
        "STYLE": null,
        "DESCRIPTION": "RDS preview check",
        "SUPPLIER": "700087",
        "ORIGIN_COUNTRY": "GB",
        "CURRENCY_CODE": "ZAR",
        "COLOUR": "08610",
        "UNIT_COST": 48.49,
        "RETAIL_PRICE": 299,
        "SIZE_CURVE_DETAIL": [
            {"SOURCE_VARIANT_REF": "RDS preview check-7", "SKU_SIZE": "S070",
             "SKU_WIDTH": "ALL", "SKU_QTY": 1, "SKU_ID": null},
            {"SOURCE_VARIANT_REF": "RDS preview check-8", "SKU_SIZE": "S080",
             "SKU_WIDTH": "ALL", "SKU_QTY": 1, "SKU_ID": null}
        ],
        "DEPARTMENT": 1517,
        "CLASS": 6892,
        "SUBCLASS": 1128
    }~', l_status, l_response);

    insert into ie_mfcs_stg_preview_check values (l_status, l_response);
    commit;
end;
/

-- 1. The status, and the validation errors if there are any.
select o.http_status, e.field, e.code, e.message
  from ie_mfcs_stg_preview_check o
  left join json_table(o.response, '$.ERRORS[*]'
           columns (field   varchar2(100)  path '$.FIELD',
                    code    varchar2(100)  path '$.CODE',
                    message varchar2(1000) path '$.MESSAGE')) e on 1 = 1;

-- 2. On a 200, the calls it would make, in order.
select c.seq, c.step_code, c.http_method, c.endpoint_path
  from ie_mfcs_stg_preview_check o,
       json_table(o.response, '$.MFCS_CALLS[*]'
           columns (seq           number         path '$.sequence',
                    step_code     varchar2(60)   path '$.stepCode',
                    http_method   varchar2(10)   path '$.method',
                    endpoint_path varchar2(1000) path '$.endpointPath')) c
 order by c.seq;

drop table ie_mfcs_stg_preview_check purge;
