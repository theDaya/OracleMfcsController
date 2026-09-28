set define off

prompt Recording what MFCS actually created against the POC draft

-- The draft has always stored the controller's response document whole, in
-- POC_STYLE_DRAFT.RESPONSE_PAYLOAD, and never read it. These columns are where
-- poc_style_pkg.apply_response unpacks the identifiers out of it, so a screen
-- can show what MFCS holds without parsing JSON in a region query.
--
-- Kept separate from the composed columns on purpose. COMPOSED_ITEM_NO and
-- COMPOSED_SKU_NO are what this console *asked for* - it numbers its own items
-- (MANL) - and MFCS_* is what came back. For a composed draft the two should be
-- equal, and the whole value of storing both is that a day when they are not is
-- visible rather than silently overwritten.

alter table poc_style_draft_sku add (
    mfcs_sku_no varchar2(30)
);

comment on column poc_style_draft_sku.mfcs_sku_no is
    'The SKU number MFCS holds, read back from the controller''s status document. Compare with COMPOSED_SKU_NO, which is what was sent.';

comment on column poc_style_draft.style is
    'The MFCS style number. An input on an AMENDED draft; written back from the response on a COMPOSED one.';

comment on column poc_style_draft.order_no is
    'The MFCS purchase order number. An input on a MODIFY_ORDER draft; written back from the response on CREATE_ALL, where MFCS allocates it at RESERVE_ORDER_NUMBER.';

prompt POC actuals column:
select count(*) as mfcs_sku_no_column
  from user_tab_columns
 where table_name = 'POC_STYLE_DRAFT_SKU' and column_name = 'MFCS_SKU_NO';
