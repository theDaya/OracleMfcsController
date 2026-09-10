set define off
set feedback off

prompt Seeding POC supplier colours and codes

-- Invented data. MFCS holds Supplier Colour (56038) and Supplier Colour Code
-- (61038) as FF - free-form text with no value list - so the tenant has nothing
-- to copy here and the POC owns the list outright.
--
-- Codes are three digits, which is not arbitrary: a five-digit style plus a
-- three-digit colour composes an eight-character item number, and the tenant's
-- own auto-generated ITEM numbers are always nine. The two namespaces cannot
-- collide by length alone.

delete from poc_supplier_colour_code;
delete from poc_supplier_colour;

-- Colour, then its codes. Several colours carry more than one code so the
-- cascade on the capture screen has something real to do - a supplier's own
-- shade reference for the same colour family.
declare
    type t_code is record (code varchar2(10), descr varchar2(120));
    type t_codes is table of t_code;

    procedure add(p_colour in varchar2, p_codes in t_codes) is
        l_colour_id number;
    begin
        insert into poc_supplier_colour (colour_name)
        values (p_colour)
        returning colour_id into l_colour_id;

        for i in 1 .. p_codes.count loop
            insert into poc_supplier_colour_code (colour_id, colour_code, code_desc)
            values (l_colour_id, p_codes(i).code, p_codes(i).descr);
        end loop;
    end;
begin
    add('Black',        t_codes(t_code('010', 'Black - standard'),
                                t_code('011', 'Black - matt'),
                                t_code('012', 'Black - patent')));
    add('Ivory',        t_codes(t_code('020', 'Ivory'),
                                t_code('021', 'Ivory - antique')));
    add('Chalk',        t_codes(t_code('025', 'Chalk')));
    add('Stone',        t_codes(t_code('030', 'Stone'),
                                t_code('031', 'Stone - washed')));
    add('Sand',         t_codes(t_code('035', 'Sand')));
    add('Taupe',        t_codes(t_code('040', 'Taupe')));
    add('Tan',          t_codes(t_code('045', 'Tan'),
                                t_code('046', 'Tan - burnished')));
    add('Cognac',       t_codes(t_code('050', 'Cognac')));
    add('Chestnut',     t_codes(t_code('055', 'Chestnut')));
    add('Chocolate',    t_codes(t_code('060', 'Chocolate'),
                                t_code('061', 'Chocolate - suede')));
    add('Navy',         t_codes(t_code('070', 'Navy'),
                                t_code('071', 'Navy - nubuck')));
    add('Denim',        t_codes(t_code('075', 'Denim')));
    add('Sky Blue',     t_codes(t_code('080', 'Sky Blue')));
    add('Teal',         t_codes(t_code('085', 'Teal')));
    add('Forest',       t_codes(t_code('090', 'Forest')));
    add('Olive',        t_codes(t_code('095', 'Olive'),
                                t_code('096', 'Olive - washed')));
    add('Khaki',        t_codes(t_code('100', 'Khaki')));
    add('Mustard',      t_codes(t_code('110', 'Mustard')));
    add('Rust',         t_codes(t_code('115', 'Rust')));
    add('Burgundy',     t_codes(t_code('120', 'Burgundy'),
                                t_code('121', 'Burgundy - patent')));
    add('Berry',        t_codes(t_code('125', 'Berry')));
    add('Blush',        t_codes(t_code('130', 'Blush')));
    add('Rose Gold',    t_codes(t_code('135', 'Rose Gold')));
    add('Silver',       t_codes(t_code('140', 'Silver')));
    add('Gunmetal',     t_codes(t_code('145', 'Gunmetal')));
    add('Pewter',       t_codes(t_code('150', 'Pewter')));
    add('Leopard',      t_codes(t_code('160', 'Leopard print')));
    add('Snake',        t_codes(t_code('165', 'Snake print')));
    add('Multi',        t_codes(t_code('900', 'Multi')));
    commit;
end;
/

prompt POC colour rows:
select (select count(*) from poc_supplier_colour) as colours,
       (select count(*) from poc_supplier_colour_code) as colour_codes
  from dual;
