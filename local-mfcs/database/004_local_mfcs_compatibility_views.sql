set define off

prompt Creating Local MFCS compatibility views

create or replace view diff_groups as
select h.diff_group_id,
       h.diff_type,
       h.diff_group_desc,
       h.dept,
       h.class,
       h.subclass,
       d.diff_id,
       d.display_seq
  from diff_group_head h
  join diff_group_detail d
    on d.diff_group_id = h.diff_group_id;

prompt Local MFCS compatibility views created
