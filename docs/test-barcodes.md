# Test barcodes

Valid EAN-13s for testing style capture. Generated 2026-09-01.

**Use each one once.** A barcode identifies exactly one item, so MFCS refuses to attach one
that is already held by another SKU - and the message it gives is misleading:

```
The record is currently locked by another user. ITEM: 1234567891019
```

That is a duplicate, not a lock. It cost a request on 2026-09-01, when a barcode from an
earlier successful run was reused on a second style. Cross a block off when you use it.

The console rejects a bad check digit before anything is created
(`INVALID_EAN13`, `FAILED_NO_SIDE_EFFECT`, no item number burned). MFCS itself only checks
*length* per `itemNumberType` - 9 for `ITEM`, 12 for `UPC-A`, 13 for `EAN13` - so the check
digit is ours to enforce, and worth enforcing: a transposed pair passes a length check and
creates a barcode no scanner will ever match, on an item that cannot be unmade.

All of these start `29`, the GS1 restricted / in-store range, so they cannot collide with a
real retail barcode.

## Block 01

| # | barcode |
| --- | --- |
| 1 | `2901000000015` |
| 2 | `2901000000022` |
| 3 | `2901000000039` |
| 4 | `2901000000046` |
| 5 | `2901000000053` |
| 6 | `2901000000060` |

## Block 02

| # | barcode |
| --- | --- |
| 1 | `2902000000012` |
| 2 | `2902000000029` |
| 3 | `2902000000036` |
| 4 | `2902000000043` |
| 5 | `2902000000050` |
| 6 | `2902000000067` |

## Block 03

| # | barcode |
| --- | --- |
| 1 | `2903000000019` |
| 2 | `2903000000026` |
| 3 | `2903000000033` |
| 4 | `2903000000040` |
| 5 | `2903000000057` |
| 6 | `2903000000064` |

## Block 04

| # | barcode |
| --- | --- |
| 1 | `2904000000016` |
| 2 | `2904000000023` |
| 3 | `2904000000030` |
| 4 | `2904000000047` |
| 5 | `2904000000054` |
| 6 | `2904000000061` |

## Block 05

| # | barcode |
| --- | --- |
| 1 | `2905000000013` |
| 2 | `2905000000020` |
| 3 | `2905000000037` |
| 4 | `2905000000044` |
| 5 | `2905000000051` |
| 6 | `2905000000068` |

## Block 06

| # | barcode |
| --- | --- |
| 1 | `2906000000010` |
| 2 | `2906000000027` |
| 3 | `2906000000034` |
| 4 | `2906000000041` |
| 5 | `2906000000058` |
| 6 | `2906000000065` |

## Block 07

| # | barcode |
| --- | --- |
| 1 | `2907000000017` |
| 2 | `2907000000024` |
| 3 | `2907000000031` |
| 4 | `2907000000048` |
| 5 | `2907000000055` |
| 6 | `2907000000062` |

## Block 08

| # | barcode |
| --- | --- |
| 1 | `2908000000014` |
| 2 | `2908000000021` |
| 3 | `2908000000038` |
| 4 | `2908000000045` |
| 5 | `2908000000052` |
| 6 | `2908000000069` |

## Block 09

| # | barcode |
| --- | --- |
| 1 | `2909000000011` |
| 2 | `2909000000028` |
| 3 | `2909000000035` |
| 4 | `2909000000042` |
| 5 | `2909000000059` |
| 6 | `2909000000066` |

## Block 10

| # | barcode |
| --- | --- |
| 1 | `2910000000017` |
| 2 | `2910000000024` |
| 3 | `2910000000031` |
| 4 | `2910000000048` |
| 5 | `2910000000055` |
| 6 | `2910000000062` |

## Making more

The check digit is the last digit. Sum the first twelve, weighting alternate digits by 3
starting from the second, then take whatever brings the total to a multiple of ten.

```python
def ean13(base12):
    s = sum(int(c) * (3 if i % 2 else 1) for i, c in enumerate(base12))
    return base12 + str((10 - s % 10) % 10)
```

```sql
-- the same check the console runs, from validation_pkg.is_valid_ean13
select case when to_number(substr(:upc, 13, 1)) =
                 mod(10 - mod((select sum(to_number(substr(:upc, level, 1))
                                        * case when mod(level, 2) = 0 then 3 else 1 end)
                                 from dual connect by level <= 12), 10), 10)
            then 'valid' else 'bad check digit' end
  from dual;
```

Non-primary barcodes can use `UPC_TYPE` `MANL`, which is free-form - no length or check-digit
rule applies. A real Office SKU carries one `EAN13` and one `MANL`.
