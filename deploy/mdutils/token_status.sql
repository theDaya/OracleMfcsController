-- Decodes the stored bearer token's own exp claim. SECRET.UPDATED_AT is not
-- trustworthy: the row is sometimes updated by hand without the token changing.
set serveroutput on size unlimited
set pagesize 0 feedback off heading off
declare
    l_tok  clob;
    l_seg  varchar2(4000);
    l_exp  number;
    l_when timestamp;
begin
    select secret_value into l_tok from secret where secret_ref = 'MFCS_BEARER_TOKEN';

    -- Middle segment of the JWT, converted from base64url to plain base64.
    l_seg := regexp_substr(dbms_lob.substr(l_tok, 3000, 1), '[^.]+', 1, 2);
    l_seg := replace(replace(l_seg, '-', '+'), '_', '/');
    l_seg := l_seg || rpad('=', mod(4 - mod(length(l_seg), 4), 4), '=');

    l_exp := to_number(json_value(
        utl_raw.cast_to_varchar2(utl_encode.base64_decode(utl_raw.cast_to_raw(l_seg))),
        '$.exp'));
    l_when := timestamp '1970-01-01 00:00:00' + numtodsinterval(l_exp, 'second');

    dbms_output.put_line('token expires (UTC) : ' || to_char(l_when, 'YYYY-MM-DD HH24:MI:SS'));
    dbms_output.put_line('now           (UTC) : ' || to_char(sys_extract_utc(systimestamp), 'YYYY-MM-DD HH24:MI:SS'));
    dbms_output.put_line('status              : ' ||
        case when l_when > sys_extract_utc(systimestamp)
             then 'VALID (' || round((cast(l_when as date) - cast(sys_extract_utc(systimestamp) as date)) * 24 * 60) || ' min left)'
             else 'EXPIRED - reissue in Postman and reload with set_token.sql' end);
end;
/
