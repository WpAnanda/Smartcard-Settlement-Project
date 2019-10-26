CREATE OR REPLACE PACKAGE Pkg_FSS_Settlement IS
-- Package header, containing public procedures and functions.
PROCEDURE DailySettlement; -- Produces deskbank file, daily banking report, terminal usage report.
PROCEDURE DailyBankingSummary(p_report_date IN DATE default sysdate);
PROCEDURE TerminalUsageReport;
PROCEDURE SendEmail(p_report_date IN DATE DEFAULT sysdate); -- Send email with the deskbank file as the attachment

END Pkg_FSS_Settlement;
/
CREATE OR REPLACE PACKAGE BODY Pkg_FSS_Settlement AS
-- Forward Declarations for private procedure and functions
PROCEDURE announceme(p_module_name VARCHAR2, 
                     p_destination VARCHAR2 default get_param('Announceme', 'Destination'));
PROCEDURE run_failed(p_remarks in VARCHAR2 DEFAULT get_param('RUN FAILED', 'Parameter'));
PROCEDURE debit_transaction(p_debit IN NUMBER);
PROCEDURE upload_lodgement_ref (p_merchantid IN NUMBER,
                                p_lodgementnum IN VARCHAR2);
PROCEDURE print_deskbank (p_record_date IN DATE DEFAULT SYSDATE);
PROCEDURE update_new_transactions;
PROCEDURE settle_transactions;
PROCEDURE check_run_table(p_program_id   IN OUT NUMBER);

FUNCTION format_bsb(p_bsb IN VARCHAR2) RETURN VARCHAR2;
FUNCTION get_lodgement_num RETURN VARCHAR2;
FUNCTION format_currency(p_currency IN NUMBER) RETURN VARCHAR2;
-- End of Forward Declarations
-- Code of all private procedure and function

PROCEDURE announceme(p_module_name VARCHAR2,
                     p_destination VARCHAR2 default get_param('Announceme', 'Destination')) is
-- Purpose: To print out message on DBP_MESSAGE_LOG (common.log) Table about where the program currently at.
--          The destination can be altered to show the message on DBMS_OUTPUT, rather than DBP_MESSAGE_LOG.
-- Author: Ananda Wijaya Putra based on Database Programming Lecture
v_message VARCHAR2(255) := get_param('Announceme', 'Message')||p_module_name;
BEGIN
    IF p_destination = get_param('Announceme', 'Destination') then -- if the destination is same, then
    common.log(v_message); -- displaying the message on dbp_message_log.
ELSE
    DBMS_OUTPUT.PUT_LINE(v_message);
END IF;
END announceme;

PROCEDURE check_run_table(p_program_id IN OUT NUMBER)IS
-- Purpose : To check if the program have been run today from the fss_run_table.
--           Because settlement can be only done once a day.
-- Author : Ananda Wijaya Putra
    v_module_name VARCHAR2(35) := get_param('CHCKRUNTBL', 'Module name');  
    v_runlogID      NUMBER;
    v_run_log_record FSS_RUN_TABLE%ROWTYPE;
    moduleRan       EXCEPTION;
BEGIN -- PLEASE READ! USING GET_PARAM on v_module_name and announceme doesnt work. USING NORMAL VARCHAR2 WORKS SO I REVERT IT BACK
    Announceme(v_module_name||get_param('CHCKRUNTBL', 'Start message')); 
    DBMS_OUTPUT.PUT_LINE('pass announce');
        BEGIN -- inner block starts
            SELECT * INTO v_run_log_record
            FROM FSS_RUN_TABLE
            WHERE RUNOUTCOME = get_param('CHCKRUNTBL', 'Run outcome')
            AND TO_CHAR(RUNEND, get_param('Date_Format', 'Date Format 1')) = TO_CHAR(sysdate,get_param('Date_Format', 'Date Format 1'));
            RAISE moduleRan; DBMS_OUTPUT.PUT_LINE('pass module ran');
        EXCEPTION 
            WHEN NO_DATA_FOUND THEN
              DBMS_OUTPUT.PUT_LINE('INSIDE NO RUN');
            p_program_id := FSS_RUNLOG_SEQ.NEXTVAL;
            INSERT INTO FSS_RUN_TABLE(RUNID, RUNSTART, RUNEND, RUNOUTCOME, REMARKS)
            VALUES (p_program_id, sysdate, NULL, NULL, get_param('CHCKRUNTBL', 'Remarks'));
            DBMS_OUTPUT.PUT_LINE('after start program' ||get_param('CHCKRUNTBL', 'Remarks') );
        END; -- inner block ends
    UPDATE FSS_RUN_TABLE -- updates fss_run_table if the settlement havent ran today, update it with success
    SET RUNEND      = sysdate,
        RUNOUTCOME  = get_param('CHCKRUNTBL', 'Run outcome'),
        REMARKS     = get_param('CHCKRUNTBL', 'Remarks2')
    WHERE RUNID = p_program_ID;
     DBMS_OUTPUT.PUT_LINE('123');
    DBMS_OUTPUT.PUT_LINE('TEST'||get_param('CHCKRUNTBL', 'Run outcome'));
    DBMS_OUTPUT.PUT_LINE(get_param('CHCKRUNTBL', 'Remarks2'));
    EXCEPTION
        WHEN moduleRan THEN -- self made exception
            p_program_ID := 0; -- assigns program id with 0, to mark that it have been run today
            announceme(get_param('CHCKRUNTBL', 'module ran')||v_run_log_record.RUNSTART);
        WHEN OTHERS THEN -- if there are exception other than the program have been ran.
            announceme(v_module_name||get_param('CHCKRUNTBL', 'exception others')||SQLERRM);
            UPDATE FSS_RUN_TABLE
            SET RUNEND      = sysdate,
                RUNOUTCOME  = get_param('CHCKRUNTBL', 'Run outcome 2'),
                REMARKS     = get_param('CHCKRUNTBL', 'Remarks 2')
            WHERE RUNID = p_program_ID;

END check_run_table;

PROCEDURE debit_transaction(p_debit IN NUMBER) IS
-- Purpose: To updates the debit transactions in FSS_DAILY_SETTLEMENT from FSS_ORGANISATION.
-- Author: Ananda Wijaya Putra
-- JUST LIKE ON CHECK_RUN_TABLE, GET PARAM DIDNT WORK ON MODULE NAME AND ANNOUNCEME.
    v_module_name   VARCHAR2(35) := get_param('DEBIT', 'Module name');
    v_lodgement_num VARCHAR2(15);
    v_account_nr    VARCHAR2(15);
    v_title         VARCHAR2(40);
    v_bsb           VARCHAR2(6);
    v_new_bsb       VARCHAR2(7);
BEGIN
    Announceme(v_module_name||get_param('DEBIT', 'Start message'));
    DBMS_OUTPUT.PUT_LINE('pass announce');
    v_lodgement_num := get_lodgement_num;
    
    SELECT ORGACCOUNTTITLE,-- selects the accounttitle, bsb, and bank account into variables
           ORGBSBNR,
           ORGBANKACCOUNT
    INTO v_title, v_bsb, v_account_nr
    FROM FSS_ORGANISATION
    WHERE ORGNR = TO_NUMBER(get_param('DEBIT', 'orgnum'));-- uses the organisation number to debit the transaction
    v_new_bsb := format_bsb(v_bsb);
    INSERT INTO FSS_DAILY_SETTLEMENT (RECORDTYPE,
                                      BSB,
                                      ACCOUNTNR,
                                      TRAN_CODE,
                                      SETTLEVALUE,
                                      MERCHANTTITLE,
                                      BANKFLAG,
                                      LODGEMENTREF,
                                      TRACENR,
                                      REMITTER,
                                      GSTTAX,
                                      SETTLEDATE)
                              VALUES (get_param('DEBIT', 'RECORDTYPE'),
                                      v_new_bsb, --inserts the FORMATTED bsb into the table
                                      v_account_nr, -- inserts the account number appointed to the variable
                                      get_param('DEBIT', 'TRANSACTIONCODE'),
                                      p_debit,
                                      v_title, -- inserts the org. title appointed to the variable
                                      get_param('DEBIT', 'BANKFLAG'),
                                      v_lodgement_num,
                                      get_param('DEBIT', 'TRACENUMBER'),
                                      get_param('DEBIT', 'REMMITER'),
                                      get_param('DEBIT', 'GSTTAX'),
                                      sysdate);
    EXCEPTION
        WHEN OTHERS THEN
            run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
END;

PROCEDURE update_new_Transactions is 
--Purpose : Upload any new transactions from the fss_transactions into fss_daily_transaction
--Author: Laurie Benkovich
v_module_name VARCHAR2(35) := get_param('UPDATETRANS', 'Module name'); 
BEGIN 
--announceme(v_module_name); 
    insert into FSS_DAILY_TRANSACTION(TRANSACTIONNR, 
                                      DOWNLOADDATE, 
                                      TERMINALID, 
                                      CARDID, 
                                      TRANSACTIONDATE, 
                                      CARDOLDVALUE, 
                                      TRANSACTIONAMOUNT, 
                                      CARDNEWVALUE, 
                                      TRANSACTIONSTATUS, 
                                      ERRORCODE) 
    SELECT t1.TRANSACTIONNR, 
           t1.DOWNLOADDATE, 
           t1.TERMINALID, 
           t1.CARDID, 
           t1.TRANSACTIONDATE, 
           t1.CARDOLDVALUE, 
           t1.TRANSACTIONAMOUNT, 
           t1.CARDNEWVALUE, 
           t1.TRANSACTIONSTATUS, 
           t1.ERRORCODE 
    from fss_transactions t1                
    where not exists (select 1                  
                      from FSS_DAILY_TRANSACTION t2                  
                      where t1.transactionnr = t2.transactionnr);
commit; 
    EXCEPTION
        WHEN OTHERS THEN
            run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
END;

PROCEDURE print_deskbank(p_record_date IN DATE DEFAULT SYSDATE) IS
-- Purpose: Create the deskbank file
-- Author: Ananda Wijaya Putra
    v_module_name   VARCHAR2(35) := get_param('deskbank', 'Module name');
    v_filename      VARCHAR2(30) := get_param('deskbank', 'File name 1')||to_char(sysdate,get_param('Date_Format', 'Date Format 2'))||get_param('deskbank', 'File name 2');
    v_input_line      VARCHAR2(150); -- buffer input data
    v_credit        NUMBER :=0;
    v_nrRecords     NUMBER :=0;
    v_debit         NUMBER :=0;
    v_file utl_file.file_type; -- file pointer

CURSOR c_settlements IS -- the cursor will be used on the deskbank body, where it will go through the cursor to input all transactions
    SELECT LODGEMENTREF,
           TRAN_CODE,
           ACCOUNTNR,
           BSB,
           SETTLEVALUE,
           MERCHANTTITLE,
           BANKFLAG
    FROM FSS_DAILY_SETTLEMENT
    WHERE TO_CHAR(SETTLEDATE)=TO_CHAR(p_record_date);
BEGIN
 Announceme(v_module_name||get_param('deskbank', 'Start message')||to_char(p_record_date, get_param('Date_Format', 'Date Format 3')));
    
    -- Print header to file
    -- The header is pretty much hard coded, therefore all of them will be accessed by get_param.
    v_file := utl_file.fopen ('U13002581_DIR', v_filename, 'W');    
    -- tried to change the v_file constants with get_param but it messes up everything
    -- v_file := utl_file.fopen(get_param('File','fopen1'), v_filename,get_param('File','write'));
    v_input_line := to_char(RPAD(get_param('Constant', 'Zero'), 18) || 
                          RPAD(get_param('Header', '1'), 12) || 
                          RPAD(get_param('Header', 'Title'), 26, get_param('Constant', 'Blank')|| 
                          get_param('Header', '034002') || 
                          RPAD(get_param('Header', 'INVOICES'), 12, get_param('Constant', 'Blank')) ||
                          to_char(sysdate, get_param('Date_Format', 'Date Format 4'))));
                          
    utl_file.put_line(v_file, v_input_line); 
    
    -- Prints the body of deskbank file
    FOR r_settlements IN c_settlements LOOP -- loop so it will go through all of the unsettled transactions.
      v_nrRecords := v_nrRecords + 1;
      v_input_line := TO_CHAR(1 ||
                            SUBSTR(r_settlements.bsb,1,3)||get_param('Constant','Dash')|| 
                            SUBSTR(r_settlements.bsb,4,3)||
                            r_settlements.ACCOUNTNR||get_param('Constant', 'Blank')||
                            RPAD(r_settlements.TRAN_CODE, 2, get_param('Constant', 'Zero'))||
                            LPAD(r_settlements.settlevalue,10,get_param('Constant', 'Zero'))||
                            RPAD(r_settlements.MERCHANTTITLE,32,get_param('Constant', 'Blank'))||
                            get_param('Constant', 'Blank')||r_settlements.BANKFLAG||get_param('Constant', 'Blank')||
                            r_settlements.lodgementref||
                            get_param('deskbank', 'body')||
                            RPAD(get_param('Constant', 'Zero'), 8, get_param('Constant', 'Zero')));
    IF r_settlements.TRAN_CODE = 50 THEN -- calculate the credit of the transactions because the code is 50
         v_credit := v_credit + r_settlements.settlevalue;
       ELSE   
         v_debit := v_debit + r_settlements.settlevalue;
       END IF;
       
       utl_file.put_line(v_file, v_input_line);
       
       EXIT WHEN v_nrRecords > 100; -- exits when the record is more than 100
    END LOOP;
    
    -- Prints footer of the deskbank file 
    v_input_line := TO_CHAR(RPAD(get_param('deskbank', 'footer'),20, get_param('Constant', 'Blank')) ||
                          RPAD(v_debit-v_credit,10,get_param('Constant', 'Zero')) ||
                          LPAD(v_credit,10,get_param('Constant', 'Zero')) ||
                          LPAD(v_debit,10,get_param('Constant', 'Zero')) ||
                          LPAD(get_param('Constant', 'Blank'),24) ||
                          LPAD(v_nrRecords,6,get_param('Constant', 'Zero')));
    utl_file.put_line(v_file, v_input_line);
        
    utl_file.fclose(v_file);
    
    EXCEPTION
      WHEN OTHERS THEN
        utl_file.fclose(v_file);
        run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));                    
       
END;

FUNCTION format_bsb (p_bsb IN VARCHAR2) RETURN VARCHAR2 IS
-- Purpose: Gives back the bsb with the correct format based on the assignment specification. From xxxxxx to xxx-xxx
-- Author: Ananda Wijaya Putra
    v_module_name   VARCHAR2(35):= get_param('BSB','Module name');
    v_new_bsb       VARCHAR2(7); -- to store the bsb
    
    BEGIN
        Announceme(v_module_name||get_param('BSB', 'Start message'));
        v_new_bsb := p_bsb;
        RETURN TO_CHAR(SUBSTR(v_new_bsb, 1, 3)||get_param('Constant','Dash')||SUBSTR(v_new_bsb, 4, 3));
   
    EXCEPTION
        WHEN OTHERS THEN
        run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
    END;
PROCEDURE settle_transactions IS
-- Purpose: Settles transaction from FSS_DAILY_TRANSACTION and update it to the FSS_DAILY_SETTLEMENT.
-- Author: Ananda Wijaya Putra
    v_module_name   VARCHAR2(35):= get_param('settle', 'Module name');
    v_credit        NUMBER:=0;
    v_nrRecords     NUMBER:=0;
    v_lodgementnum  VARCHAR2(15);
    v_new_bsb       VARCHAR2(7);
    no_settlements  EXCEPTION;

    v_minimum_settle NUMBER;
    v_file utl_file.file_type;
CURSOR c_merchant_total IS -- getting non hard coded data from fss_merchant and fss_terminal and daily_transaction for daily settlement table.
    SELECT m.MERCHANTBANKBSB bsb, 
           m.MERCHANTBANKACCNR account,
           SUBSTR(m.MERCHANTLASTNAME, 1, 32) Name,
           m.MERCHANTID merchantid,
           SUM(DT.TRANSACTIONAMOUNT) total
    FROM fss_merchant m JOIN fss_terminal T ON m.MERCHANTID = T.MERCHANTID 
    JOIN FSS_DAILY_TRANSACTION DT ON T.TERMINALID = DT.TERMINALID 
    WHERE lodgementref is NULL -- only obtaining unsettled transaction
    GROUP BY m.MERCHANTLASTNAME, m.MERCHANTID, m.MERCHANTBANKBSB, m.MERCHANTBANKACCNR;

r_merchant_total c_merchant_total%ROWTYPE;    

BEGIN
    Announceme(v_module_name||get_param('settle', 'Start message'));
    -- Convert to number, and getting minimum value for settling transaction
    SELECT TO_NUMBER(REPLACE(REFERENCEVALUE,get_param('Constant', 'Dot'))) INTO v_minimum_settle
    FROM FSS_REFERENCE WHERE REFERENCEID=get_param('settle', 'Reference ID');
    
    -- Loop through account that havent been settled
    FOR r_merchant_total IN c_merchant_total LOOP
        IF r_merchant_total.total > v_minimum_settle THEN
        v_credit := v_credit + r_merchant_total.total; -- total of credit
        v_nrRecords := v_nrRecords + 1; -- total of records
        v_lodgementnum := get_lodgement_num;
        v_new_bsb := format_bsb(r_merchant_total.bsb); -- to format the bsb
        
    
    INSERT INTO FSS_DAILY_SETTLEMENT(LODGEMENTREF,
                                     RECORDTYPE,
                                     BSB,
                                     ACCOUNTNR,
                                     TRAN_CODE,
                                     SETTLEVALUE,
                                     MERCHANTID,
                                     MERCHANTTITLE,
                                     BANKFLAG,
                                     TRACENR,
                                     REMITTER,
                                     GSTTAX,
                                     SETTLEDATE)
    VALUES (v_lodgementnum,
            1,
            v_new_bsb,
            r_merchant_total.account,
            50,
            r_merchant_total.total,
            r_merchant_total.merchantid,
            r_merchant_total.name,
            get_param('settle', 'bankflag'),
            get_param('settle', 'tracenr'),
            get_param('settle', 'remitter'),
            get_param('settle', 'gsttax'),
            sysdate);
    -- Upload lodgement number for each transactions
    upload_lodgement_ref(r_merchant_total.merchantid, v_lodgementnum);
    END IF;
    EXIT WHEN v_nrRecords > 50;
    END LOOP;
    
    -- Calculate debit amount
    IF v_nrRecords > 0 THEN
       v_nrRecords := v_nrRecords + 1;
       
       debit_transaction(v_credit);
       COMMIT;
       
    ELSE
    -- If counter 0, then exception raised, meaning there is no unsettled settlements to settle.
    RAISE no_settlements;
    END IF;
    EXCEPTION
        WHEN no_settlements THEN
            common.log(get_param('settle', 'nosettlements')||to_char(sysdate));
        WHEN OTHERS THEN
            run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
END;

FUNCTION get_lodgement_num RETURN VARCHAR2 IS
-- Purpose: To return the lodgement number from FSS_LODGEMENTNUM with date.
-- Author: Ananda Wijaya Putra
v_module_name VARCHAR2(35) := get_param('getlodgenum','Module name');
BEGIN
    Announceme(v_module_name||get_param('getlodgenum','Start message'));
    RETURN TO_CHAR(TO_CHAR(sysdate, get_param('Date_Format','Date Format 5'))|| LPAD(FSS_LODGEMENTNUM_SEQ.NEXTVAL, 7, get_param('Constant', 'Zero'))); -- seven zeroes.

EXCEPTION
    WHEN OTHERS THEN
    run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
END;

PROCEDURE upload_lodgement_ref(p_merchantid IN NUMBER,
                               p_lodgementnum IN VARCHAR2) IS
-- Purpose: To update FSS_DAILY_TRANSACTION with the lodgement reference number, marking settled transactions so there is no repetition.
-- Author: Ananda Wijaya Putra
v_module_name VARCHAR2(35) := get_param('UPLOADLODGENUM', 'Module name');
BEGIN
    Announceme(v_module_name||get_param('UPLOADLODGENUM', 'Start message 1')||p_lodgementnum||get_param('UPLOADLODGENUM', 'Start message 2')||p_merchantid);
    UPDATE FSS_DAILY_TRANSACTION DT -- it updates this table because this table saves the lodgement reference number
        SET DT.LODGEMENTREF = p_lodgementnum
        WHERE EXISTS (SELECT p_merchantid
                      FROM FSS_TERMINAL T
                      WHERE DT.TERMINALID=T.TERMINALID -- joins
                      AND T.MERCHANTID=p_merchantid
                      AND DT.LODGEMENTREF IS NULL); -- null so it didn't overwrite the existing lodgement reference number
EXCEPTION
    WHEN OTHERS THEN
        run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
END;

PROCEDURE run_failed(p_remarks IN VARCHAR2 DEFAULT get_param('RUN FAILED', 'Parameter')) IS
-- Purpose: To update FSS_RUN_TABLE if the run failed
-- Author: Ananda Wijaya Putra, referenced from Kaz Yamada on GitHub
v_runLogID      NUMBER;
v_module_name   VARCHAR2(35) := get_param('RUN FAILED', 'Module name');
BEGIN
    Announceme(v_module_name||get_param('Constant', 'Blank')||p_remarks);
    SELECT RUNID INTO v_runLogID FROM FSS_RUN_TABLE -- initialise fss_run_table
    WHERE TO_CHAR(RUNEND) = TO_CHAR(SYSDATE); -- runend is sysdate
    UPDATE FSS_RUN_TABLE -- update with the fail status
    SET RUNEND      = sysdate,
        RUNOUTCOME  = get_param('RUN FAILED', 'Run outcome'),
        REMARKS     = p_remarks
    WHERE RUNID = v_runLogID;
END;

PROCEDURE DailySettlement IS
-- Purpose: Calculate all of the unsettled transactions, printing the deskbank file, daily banking summary, and terminal usage report
-- Author: Ananda Wijaya Putra
    v_module_name VARCHAR2(35) := get_param('DailySettlement','Module name');
    v_program_ID NUMBER;
    v_run_data   FSS_RUN_TABLE%ROWTYPE;
BEGIN
    announceme(v_module_name);
    --DBMS_OUTPUT.PUT_LINE('announceme'); -- the purpose of these dbms_output is for debug.
    check_run_table(v_program_id); -- check if the program have been run today
    --DBMS_OUTPUT.PUT_LINE('checkRun');
    update_new_Transactions; -- update new transactions that havent been settled
    --DBMS_OUTPUT.PUT_LINE('updateTrans');
    settle_transactions; -- settles the unsettled transactions
    --DBMS_OUTPUT.PUT_LINE('settleTrans');

    print_deskbank; -- creates the deskbank
    dailybankingsummary; -- creates the daily banking summary
    terminalusagereport; -- creates the terminal usage report
END;

FUNCTION format_currency(p_currency IN NUMBER) RETURN VARCHAR2 IS
-- Purpose: To show the currency in decimal format (cents) and add a dollar sign 
-- Author: Ananda Wijaya Putra
v_module_name VARCHAR2(35) := get_param('Format Currency', 'Module name');
BEGIN
    RETURN TO_CHAR(get_param('Constant','Dollar')||SUBSTR(p_currency,0,length(p_currency)-2) -- putting the dollar sign and finding the numbers last two numbers and put a dot on it.
           ||get_param('Format Currency', 'dot')||
           SUBSTR(p_currency, -2, 2)); -- continues the number with the last two numbers
EXCEPTION
    WHEN OTHERS THEN
        run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
END;

PROCEDURE DailyBankingSummary (p_report_date IN DATE default sysdate)IS
-- Purpose: To create a daily banking summary based on deskbank file.
-- Author: Ananda Wijaya Putra
v_module_name       VARCHAR2(19) := get_param('DailyBankingSummary', 'Module name');
v_filename          VARCHAR2(38) := '13002581_DSREP_'||to_char(sysdate,'DDMMYYYY')||'.rpt';
-- v_filename didnt use get_param because of unknown error.
v_deskbank_filename VARCHAR2(30) := '13002581_DS_'||to_char(p_report_date,'DDMMYYYY')||'.dat';
-- v_deskbank_filename didnt use get_param because of unknown error.
v_input_line        VARCHAR2(120); -- buffer line
v_currency          VARCHAR2(12);
v_total_credit      NUMBER := 0;
v_total_debit       NUMBER := 0;
v_counter           NUMBER := 0;
v_file utl_file.file_type; -- utl pointer

CURSOR c_settlements IS -- fetching all neccessary data from fss_daily_settlement to create daily banking summmary
    SELECT BSB, MERCHANTID, MERCHANTTITLE, ACCOUNTNR, SETTLEVALUE, TRAN_CODE
    FROM   FSS_DAILY_SETTLEMENT
    WHERE  TO_CHAR(SETTLEDATE) = TO_CHAR(P_REPORT_DATE)
    AND LODGEMENTREF IS NOT NULL;

r_settle_record c_settlements%ROWTYPE;
BEGIN
Announceme(v_module_name||get_param('DailyBankingSummary', 'Start message')||to_char(p_report_date, get_param('Date_Format', 'Date Format 1')));
v_file := utl_file.fopen ('U13002581_DIR',v_filename,'W');
    -- Deskbank Summary titles
    v_input_line := LPAD(get_param('Constant', 'Blank'), 30, get_param('Constant', 'Blank')) || get_param('DailyBankingSummary', 'Title 1');
    utl_file.put_line(v_file, v_input_line);    
    v_input_line := LPAD(get_param('Constant', 'Blank'), 32, get_param('Constant', 'Blank')) || get_param('DailyBankingSummary', 'Title 2');
    utl_file.put_line(v_file, v_input_line);
    
    -- Date and page number
    v_input_line := TO_CHAR('Date '||
                          TO_CHAR(sysdate,get_param('Date_Format', 'Date Format 1'))) ||
                          LPAD(get_param('DailyBankingSummary', 'Page'), 75, get_param('Constant', 'Blank'));    
    utl_file.put_line(v_file, v_input_line);
    
    -- Header row for summary
    -- Header row pretty much is all hard-coded, will be called by get_param
    utl_file.put_line(v_file, '');    
    v_input_line := common.f_centre(get_param('DBHeader','ID'), 11)||
                  common.f_centre(get_param('DBHeader','Name'), 35)||
                  common.f_centre(get_param('DBHeader','AccNr'), 34)||
                  common.f_centre(get_param('DBHeader','Dbt'), 18)||
                  common.f_centre(get_param('DBHeader','Cred'), 25);
    utl_file.put_line(v_file, v_input_line);   
    
    v_input_line := RPAD(get_param('Constant','Dash'), 11, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 32, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 14, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 15, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 15, get_param('Constant','Dash'));    
    utl_file.put_line(v_file, v_input_line);
    
    -- Print records    
    FOR r_settle_record IN c_settlements LOOP
      v_input_line := RPAD(NVL(to_char(r_settle_record.merchantid),get_param('Constant', 'Blank')), 12, get_param('Constant', 'Blank'))||
                    RPAD(r_settle_record.MERCHANTTITLE, 33, get_param('Constant', 'Blank')) ||
                    RPAD(r_settle_record.BSB||r_settle_record.ACCOUNTNR, 15, get_param('Constant', 'Blank'));
      v_currency := format_currency(r_settle_record.SETTLEVALUE);

      -- Check if debit or credit 
      IF r_settle_record.TRAN_CODE = 13 THEN
        v_total_debit := v_total_debit + r_settle_record.SETTLEVALUE;
        v_input_line := v_input_line || LPAD(v_currency, 15, get_param('Constant', 'Blank'));
      ELSE
        v_total_credit := v_total_credit + r_settle_record.SETTLEVALUE;
        v_input_line := v_input_line ||
                      LPAD(get_param('Constant', 'Blank'), 15, get_param('Constant', 'Blank')) ||
                      LPAD(v_currency, 16, get_param('Constant', 'Blank'));
      END IF;
      utl_file.put_line(v_file, v_input_line);
      
      v_counter := v_counter + 1;
      EXIT WHEN v_counter > 100;
    END LOOP;
    
    v_input_line := RPAD(get_param('Constant', 'Blank'), 60, get_param('Constant', 'Blank'))||
                  RPAD(get_param('Constant','Dash'), 15, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 15, get_param('Constant','Dash')); 
    utl_file.put_line(v_file, v_input_line);  

    -- Print totals
    v_currency := format_currency(v_total_debit);
    v_input_line := RPAD(get_param('DailyBankingSummary','Total Balance'), 60, get_param('Constant', 'Blank'))||
                  LPAD(v_currency, 15, get_param('Constant', 'Blank'))||get_param('Constant', 'Blank');   

    v_currency := format_currency(v_total_credit);
    v_input_line := v_input_line||LPAD(v_currency, 15, get_param('Constant', 'Blank'));
    utl_file.put_line(v_file, v_input_line);
    -- showing the daily banking summary file name
    v_input_line := get_param('DailyBankingSummary','DS file name')|| v_deskbank_filename;
    utl_file.put_line(v_file, v_input_line);
    -- showing the date report
    v_input_line := get_param('DailyBankingSummary','Dispatch Date')||LPAD(': ',8,get_param('Constant', 'Blank'))|| to_char(p_report_date, get_param('Date_Format','Date Format 7'));
    utl_file.put_line(v_file, v_input_line);
   
    -- Print end of file
    utl_file.put_line(v_file, '');
    v_input_line := LPAD(get_param('Constant', 'Blank'), 30, get_param('Constant', 'Blank')) ||get_param('DailyBankingSummary','Footer');
    utl_file.put_line(v_file, v_input_line);
    
    utl_file.fclose(v_file);      
  END;

PROCEDURE TerminalUsageReport IS
-- Purpose: Finding which terminal is busiest and where the money flows the most and sort them descendingly.
-- Author: Ananda Wijaya Putra
v_module_name   VARCHAR2(20) := get_param('TUREP', 'Module name');
v_filename      VARCHAR2(35) := '13002581_TUREP_'||to_char(sysdate,'DDMMYYYY')||'.rpt';
v_currency      VARCHAR2(35);
v_input_line      VARCHAR2(250);
v_file utl_file.file_type;

CURSOR c_terminals IS -- cursor that needs to access a lot of data from various tables, and will be put on the terminal usage report.
    SELECT DT.TERMINALID terminalid, TT.TYPENAME terminaltype, 
           TT.TYPEDESCRIPTION terminalname, DS.MERCHANTTITLE merchantname, 
           COUNT(*) transactionnum, SUM(SETTLEVALUE)totalamt
    FROM   FSS_DAILY_SETTLEMENT DS          JOIN FSS_DAILY_TRANSACTION DT -- uses table daily settlement and daily transaction
    ON DS.LODGEMENTREF = DT.LODGEMENTREF    JOIN FSS_TERMINAL T -- also fss_terminal
    ON DT.TERMINALID = T.TERMINALID         JOIN FSS_TERMINAL_TYPE TT -- and also fss_terminal_type
    ON TT.TYPENAME = T.TERMINALTYPE
    WHERE TRAN_CODE = '50' AND -- to show credit transactions
          TO_CHAR(SETTLEDATE, get_param('Date_Format', 'Date Format 6')) = TO_CHAR(SYSDATE, get_param('Date_Format', 'Date Format 6'))
    GROUP BY DT.TERMINALID, -- group by have to be same as the select statement
             TT.TYPENAME,
             TT.TYPEDESCRIPTION,
             DS.MERCHANTTITLE
    ORDER BY SUM(SETTLEVALUE) DESC; -- the turep will sort based on the settlevalue (descending)
    
r_terminals_record c_terminals%ROWTYPE;

BEGIN
Announceme(v_module_name||get_param('TUREP','Start message')||to_char(sysdate, get_param('Date_Format', 'Date Format 1')));
v_file := utl_file.fopen ('U13002581_DIR',v_filename,'W'); --creates a file in the directory
    -- Start of the header
    v_input_line := LPAD(get_param('Constant', 'Blank'), 43, get_param('Constant', 'Blank')) || get_param('TUREP', 'Title 1');
    utl_file.put_line(v_file, v_input_line);    
    v_input_line := LPAD(get_param('Constant', 'Blank'), 45, get_param('Constant', 'Blank')) || get_param('TUREP', 'Title 2');
    utl_file.put_line(v_file, v_input_line);
    
    v_input_line := TO_CHAR(get_param('TUREP', 'Header Date')||
                          TO_CHAR(sysdate, get_param('Date_Format', 'Date Format 1'))) ||
                          LPAD(get_param('TUREP','Header Page'), 89, get_param('Constant', 'Blank'));
    utl_file.put_line(v_file, v_input_line);                      
    v_input_line := TO_CHAR(get_param('TUREP', 'Header Usage')||
                          TO_CHAR(sysdate, get_param('Date_Format', 'Date Format 6')));
    -- end of the header.
    utl_file.put_line(v_file, v_input_line); -- to give a space of a row in the file
    utl_file.put_line(v_file, '');
    --table header part 1
    v_input_line := common.f_centre(get_param('TUREP','Category1'), 10)||
                  common.f_centre(get_param('TUREP','Category2'), 10)||
                  common.f_centre(get_param('TUREP','Category3'), 24)||
                  common.f_centre(get_param('TUREP','Category4'), 43)||
                  common.f_centre(get_param('TUREP','Category5'), 52)||
                  common.f_centre(get_param('TUREP','Category6'), 22); 
    utl_file.put_line(v_file, v_input_line);   
    --table header part 2
    v_input_line := common.f_centre('', 10)||
                  common.f_centre(get_param('TUREP','Cat2'), 30)||
                  common.f_centre(get_param('TUREP','Cat3'), 27)||
                  common.f_centre(get_param('TUREP','Cat4'), 45)||
                  common.f_centre(get_param('TUREP','Cat5'), 55)||
                  common.f_centre(get_param('TUREP','Cat6'), 22); 
    utl_file.put_line(v_file, v_input_line);
    -- the formatting of the dash and the blanks
    v_input_line := RPAD(get_param('Constant','Dash'), 10, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 8, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 25, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 35, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 14, get_param('Constant','Dash'))||get_param('Constant', 'Blank')||
                  RPAD(get_param('Constant','Dash'), 16, get_param('Constant','Dash'));
    utl_file.put_line(v_file, v_input_line);
    -- Start of the actual body and terminal data in terminal usage report
     FOR r_terminals_record IN c_terminals LOOP
     v_currency := format_currency(r_terminals_record.TOTALAMT);
     v_input_line :=  RPAD(r_terminals_record.TERMINALID, 14, get_param('Constant', 'Blank'))||
                    RPAD(r_terminals_record.TERMINALTYPE, 6, get_param('Constant', 'Blank')) ||
                    RPAD(r_terminals_record.TERMINALNAME, 26, get_param('Constant', 'Blank'))||
                    RPAD(r_terminals_record.MERCHANTNAME, 41, get_param('Constant', 'Blank'))||
                    RPAD(r_terminals_record.TRANSACTIONNUM, 14, get_param('Constant', 'Blank'))||
                    RPAD(v_currency, 13, get_param('Constant', 'Blank'));
    utl_file.put_line(v_file, v_input_line);
    END LOOP;
    -- Start footer of terminal usage report
    utl_file.put_line(v_file, ''); -- gives a blank row in the document
    v_input_line := LPAD(get_param('Constant', 'Blank'), 30, get_param('Constant', 'Blank')) ||get_param('TUREP','Footer');
    utl_file.put_line(v_file, v_input_line);
    utl_file.fclose(v_file); -- closes the file
END;

PROCEDURE SendEmail(p_report_date IN DATE DEFAULT sysdate) is
-- Purpose: Send daily banking summary to a specified email.
-- Author: Ananda Wijaya Putra, based on UTS ONLINE
-- nearly all of the variables are hard-coded, therefore will be called by get_param
-- the sendemail procedure mostly adapts laurie's code, but it is modified on certain parts to be able to send a txt attachment.
  v_module_name     VARCHAR2(35) := get_param('SendEmail','Module Name');
  con_email_server  VARCHAR2(50) := get_param('SendEmail','Email Server'); -- determines which email server to connect.
  con_nl            VARCHAR2(2) := CHR(13)||CHR(10);
  con_email_footer  VARCHAR2(250) := get_param('SendEmail','Footer');
    
  v_connection UTL_SMTP.CONNECTION;
  v_subject         VARCHAR2(50) := get_param('SendEmail','Subject')||to_char(p_report_date , get_param('Date_Format','Date Format 1'));
  v_recipient       VARCHAR2(40) := get_param('SendEmail','Recipient'); -- determines the recipient
  v_sender          VARCHAR2(40) := get_param('SendEmail','Sender'); -- determines the sender
  v_attachment      VARCHAR2(35) := get_param('SendEmail','Attachment')||TO_CHAR(p_report_date,get_param('Date_Format', 'Date Format 2'))||get_param('SendEmail','rpt'); -- the actual file name
  v_txtattach       VARCHAR2(35) := get_param('SendEmail','Attachment')||TO_CHAR(p_report_date,get_param('Date_Format', 'Date Format 2'))||get_param('SendEmail','txt'); -- the file will be converted to txt with this variable
  v_boundary_text   VARCHAR2(25) := get_param('SendEmail','Boundary');
  v_loc             VARCHAR2(255);
  v_input_line      VARCHAR2(200);
  v_file utl_file.file_type;

BEGIN
  v_connection := UTL_SMTP.OPEN_CONNECTION(con_email_server, 25);
  UTL_SMTP.HELO(v_connection,con_email_server);
  UTL_SMTP.MAIL(v_connection, v_recipient);
  UTL_SMTP.rcpt (v_connection, v_recipient);
  
  v_file := UTL_FILE.FOPEN('U13002581_DIR',v_attachment,'R'); -- you have to open the file first and change the permission to R to send the file
  
  v_loc := 'Position 1';    
  UTL_SMTP.OPEN_DATA(v_connection);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','From') || get_param('Constant','colon') || v_sender|| con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','To')||v_recipient||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Subject')||v_subject||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Mime')||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Type1')||v_boundary_text||get_param('Constant','Quotations')||con_nl||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Constant','Dash2')||v_boundary_text||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Type2')||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, con_nl||get_param('Content','Send')||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Send2')||con_nl||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Regards')||con_nl||get_param('Content','Database')||con_nl||con_nl);
  UTL_SMTP.write_data(v_connection, con_nl || con_email_footer||con_nl||con_nl);
--
  v_loc := 'Position 2';
  UTL_SMTP.WRITE_DATA(v_connection, con_nl||get_param('Constant','Dash2')||v_boundary_text||con_nl);
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Type3')|| v_txtattach ||get_param('Constant','Quotations')||con_nl); -- here its using variable txtattach because it want to be in TXT format.
  UTL_SMTP.WRITE_DATA(v_connection, get_param('Content','Type4')||con_nl||con_nl);
 --
  IF UTL_FILE.IS_OPEN(v_file)THEN
  LOOP
    BEGIN
        UTL_FILE.GET_LINE(v_file,v_input_line);
        UTL_SMTP.write_data(v_connection,v_input_line||con_nl);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
    EXIT; END;
    END LOOP;
    END IF;
  UTL_SMTP.WRITE_DATA(v_connection,con_nl||get_param('Constant','Dash2')||v_boundary_text||get_param('Constant','Dash2')||con_nl);
  UTL_SMTP.CLOSE_DATA(v_connection);
  UTL_SMTP.quit (v_connection);
  utl_file.fclose(v_file); 
  common.log(get_param('Email sent','Email sent.'));
EXCEPTION
   WHEN OTHERS THEN
   run_failed(TO_CHAR(get_param('DEBIT', 'Error message 1')||v_module_name||get_param('DEBIT', 'Error message 2')||SQLERRM));
   UTL_SMTP.close_data(v_connection);
END;

END Pkg_FSS_Settlement;


