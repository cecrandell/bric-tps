WITH working_fintrans AS (
    SELECT
        ft.revenue_date,
        ft.customer_agency_id,
        ft.road_agency_id,
        ft.transaction_type_code,
        ft.transaction_type_id,
        ft.transaction_status_id,
        SUM(ft.trx_amount) trx_amount,
        COUNT(1) num_of_trx,
        SUM(
            NVL(ind_pri_funds, 0.00) + NVL(ind_trx_funds, 0.00)
        ) funds_change,
        SUM(
            NVL(ind_pri_receivable_count, 0.00) + NVL(ind_trx_receivable_count, 0.00)
        ) receivable_count_change,
        SUM(
            NVL(ind_pri_receivables, 0.00) + NVL(ind_trx_receivables, 0.00)
        ) receivable_change
    FROM
        financial_transaction ft
    WHERE
        $ X { [GREATER, ft.revenue_date, Start_Revenue_Date} AND $X{LESS],
        ft.revenue_date,
        End_Revenue_Date }
    GROUP BY
        ft.revenue_date,
        ft.customer_agency_id,
        ft.road_agency_id,
        ft.transaction_type_code,
        ft.transaction_type_id,
        ft.transaction_status_id
    ORDER BY
        ft.customer_agency_id,
        ft.road_agency_id,
        ft.revenue_date
),
working_tran_code AS (
    SELECT
        DISTINCT wtc.GL_TRAN_CODE_ID GL_TRAN_CODE_ID,
        wtc.GL_KEY GL_KEY,
        wtc.GL_OBJ GL_OBJ,
        wtc.JL_KEY JL_KEY,
        wtc.JL_OBJ JL_OBJ,
        wtc.GL_DESCRIPTION GL_DESCRIPTION,
        wtc.GL_GROUP GL_GROUP,
        wtc.IS_CREDIT IS_CREDIT,
        wtc.USE_ALLOCATION USE_ALLOCATION,
        wtc.ROAD_AGENCY_ID ROAD_AGENCY_ID,
        wtc.CUSTOMER_AGENCY_ID CUSTOMER_AGENCY_ID,
        wtc.EQUIPMENT_AGENCY_ID EQUIPMENT_AGENCY_ID,
        wtc.REFUND_AGENCY_ID REFUND_AGENCY_ID,
        wtc.DEPOSIT_AGENCY_ID DEPOSIT_AGENCY_ID,
        wtc.ACCOUNT_TYPE_CODE ACCOUNT_TYPE_CODE,
        wtc.ACCOUNT_SUBTYPE_CODE ACCOUNT_SUBTYPE_CODE,
        wtc.TRANSACTION_TYPE_CODE TRANSACTION_TYPE_CODE,
        wtc.IS_ACCRUAL IS_ACCRUAL
    FROM
        gl_tran_code wtc
        INNER JOIN working_fintrans wft ON wtc.transaction_type_code = wft.transaction_type_code
),
summary_fintrans AS (
    SELECT
        ft.customer_agency_code,
        gltc.gl_tran_code_id,
        ft.road_agency_code,
        SUM(trx_amount) tcr_amount,
        SUM(num_of_trx) ft_num_of_trans,
        SUM(
            CASE
                WHEN gltc.is_credit = 1 THEN CASE
                    WHEN gla.gl_allocation_id IS NOT NULL
                    AND gltc.use_allocation = 1 THEN CASE
                        WHEN gla.use_remainder = 1 THEN (
                            ft.trx_amount - round(
                                (
                                    round(ft.trx_amount * 100, 0) * (1.0 - gla.pct_allocation)
                                ) / 100,
                                2
                            )
                        )
                        ELSE (
                            round(
                                (
                                    round(ft.trx_amount * 100, 0) * gla.pct_allocation
                                ) / 100,
                                2
                            )
                        )
                    END
                    ELSE ft.trx_amount
                END
                ELSE 0.00
            END
        ) ft_credit_amount,
        SUM(
            CASE
                WHEN gltc.is_credit != 1 THEN CASE
                    WHEN gla.gl_allocation_id IS NOT NULL
                    AND gltc.use_allocation = 1 THEN CASE
                        WHEN gla.use_remainder = 1 THEN (
                            ft.trx_amount - (
                                round(
                                    (
                                        round(ft.trx_amount * 100, 0) * (1.0 - gla.pct_allocation)
                                    ) / 100,
                                    2
                                )
                            )
                        )
                        ELSE (
                            round(
                                (
                                    round(ft.trx_amount * 100, 0) * gla.pct_allocation
                                ) / 100,
                                2
                            )
                        )
                    END
                    ELSE ft.trx_amount
                END
                ELSE 0.00
            END
        ) ft_debit_amount
    FROM
        working_fintrans ft
        LEFT OUTER JOIN working_tran_code gltc ON gltc.transaction_type_code = ft.transaction_type_code
    WHERE
        ft.transaction_status_id = (
            SELECT
                id
            FROM
                code_attribute
            WHERE
                discriminator = 'transaction.status'
                AND code = 'completed'
                AND to_char(is_active) in ('Y', '1')
        )
    GROUP BY
        ft.customer_agency_code,
        gltc.gl_tran_code_id,
        ft.road_agency_code
    ORDER BY
        ft.transaction_type_code,
)
SELECT
    gl_description,
    transaction_type_code,
    customer_agency_code,
    road_agency_code,
    refund_agency_code,
    account_type,
    account_subtype,
    sum_num_of_trans,
    sum_tcr_amount,
    debit_amount,
    credit_amount,
    net_amount
FROM
    (
        SELECT
            tca_gl.gl_group gl_agency,
            CASE
                WHEN tca_gl.jl_key IS NOT NULL THEN tca_gl.gl_key || '-' || tca_gl.gl_obj || '-' || tca_gl.jl_key || '-' || tca_gl.jl_obj
                ELSE tca_gl.gl_key || '-' || tca_gl.gl_obj
            END globj_jlobj,
            tca_gl.gl_description,
            sft.transaction_type_code,
            sft.customer_agency_code,
            sft.road_agency_code,
            sft.deposit_agency_code,
            sft.equipment_agency_code,
            sft.refund_agency_code,
            sft.account_type,
            sft.account_subtype,
            SUM(sft.ft_num_of_trans) sum_num_of_trans,
            SUM(sft.tcr_amount) sum_tcr_amount,
            SUM(NVL(sft.ft_debit_amount, 0.00)) debit_amount,
            SUM(NVL(sft.ft_credit_amount, 0.00)) credit_amount,
            SUM(
                NVL(sft.ft_debit_amount, 0.00) - NVL(sft.ft_credit_amount, 0.00)
            ) net_amount
        FROM
            gl_tca_code tca_gl
            INNER JOIN summary_fintrans sft ON tca_gl.gl_group = sft.gl_group
            AND tca_gl.gl_key = sft.gl_key
            AND tca_gl.gl_obj = sft.gl_obj
        GROUP BY
            grouping sets (
                (
                    sft.transaction_type_code,
                    tca_gl.gl_group,
                    CASE
                        WHEN tca_gl.jl_key IS NOT NULL THEN tca_gl.gl_key || '-' || tca_gl.gl_obj || '-' || tca_gl.jl_key || '-' || tca_gl.jl_obj
                        ELSE tca_gl.gl_key || '-' || tca_gl.gl_obj
                    END,
                    tca_gl.gl_description,
                    sft.customer_agency_code,
                    sft.road_agency_code,
                    sft.deposit_agency_code,
                    sft.equipment_agency_code,
                    sft.refund_agency_code,
                    sft.account_type,
                    sft.account_subtype
                ),
                ()
            )
        ORDER BY
            tca_gl.gl_group,
    )
ORDER BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10