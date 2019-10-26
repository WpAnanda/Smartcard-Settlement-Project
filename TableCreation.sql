
DROP TABLE DBP_PARAMETER;
SELECT * FROM DBP_PARAMETER;
CREATE TABLE DBP_PARAMETER 
(CATEGORY       VARCHAR2(35), 
 code           VARCHAR2(35), 
 VALUE          VARCHAR2(150), 
 ACTIVE         VARCHAR2(1) default 'Y' CONSTRAINT active_CK CHECK (active IN('Y','N')), 
 CREATED        DATE  default sysdate, 
 Modified_by    VARCHAR2(25) default USER 
); 
    
alter table dbp_parameter drop constraint active_ck;

DROP TABLE FSS_DAILY_TRANSACTION;
CREATE TABLE FSS_DAILY_TRANSACTION(
    LODGEMENTREF        VARCHAR2(15),
    TRANSACTIONNR       NUMBER,
    DOWNLOADDATE        DATE,
    TERMINALID          VARCHAR2(10),
    CARDID              VARCHAR2(17),
    TRANSACTIONDATE     DATE,
    CARDOLDVALUE        NUMBER,
    TRANSACTIONAMOUNT   NUMBER,
    CARDNEWVALUE        NUMBER,
    TRANSACTIONSTATUS   VARCHAR2(1),
    ERRORCODE           VARCHAR2(25))

DROP TABLE FSS_DAILY_SETTLEMENT;
CREATE TABLE FSS_DAILY_SETTLEMENT(
    RECORDTYPE      VARCHAR2(1),      
    BSB             VARCHAR2(7),
    ACCOUNTNR       VARCHAR2(10),
    TRAN_CODE       NUMBER,
    SETTLEVALUE     NUMBER,
    MERCHANTTITLE   VARCHAR2(32),
    BANKFLAG        VARCHAR2(3),
    LODGEMENTREF    VARCHAR2(15),
    TRACENR         VARCHAR2(16),
    REMITTER        VARCHAR2(16),
    GSTTAX          VARCHAR2(8),
    SETTLEDATE      DATE,
    MERCHANTID      NUMBER,
    MERCHANTNAME    VARCHAR2(35),
    ACCOUNTNUMBER   VARCHAR2(20),
    DEBIT           NUMBER,
    CREDIT          NUMBER)

DROP TABLE FSS_RUN_TABLE;
CREATE TABLE FSS_RUN_TABLE(
    RUNID       NUMBER          PRIMARY KEY,
    RUNSTART    DATE            NOT NULL,
    RUNEND      DATE,
    RUNOUTCOME  VARCHAR2(15),
    REMARKS     VARCHAR2(255))
    
CREATE SEQUENCE FSS_RUNLOG_SEQ
    START WITH 1
    MAXVALUE 99999999
    INCREMENT BY 1;
DROP SEQUENCE FSS_RUNLOG_SEQ;

CREATE SEQUENCE FSS_LODGEMENTNUM_SEQ
    START WITH 1
    MAXVALUE 99999999
    INCREMENT BY 1;
DROP SEQUENCE FSS_LODGEMENTREF_SEQ;

SELECT * FROM FSS_TERMINAL_TYPE;
SELECT * FROM FSS_TERMINAL;
SELECT * FROM FSS_DAILY_SETTLEMENT;
SELECT * FROM FSS_MERCHANT;
select * from dbp_message_log;
 insert into dbp_parameter 
 ( CATEGORY, 
 CODE, 
 VALUE) 
 values 
 ('SendEmail', 
  'Attachment', 
  '13002581_DSREP_'); 
  
  insert into dbp_parameter 
 ( CATEGORY, 
 CODE, 
 VALUE) 
 values 
 ('BSB', 
  'Start message', 
  '. Formatting BSB.');
  
select * from FSS_RUN_TABLE;  
select * from FSS_ORGANISATION;
select * from fss_daily_settlement;
set serveroutput on

create or replace function get_param(p_category VARCHAR2,
                                     p_code VARCHAR2)
RETURN VARCHAR2 IS
v_value VARCHAR2(150);

BEGIN
    SELECT value INTO v_value
    from dbp_parameter
    where category = p_category
    and code = p_code;
RETURN v_value;
END;

exec Pkg_FSS_Settlement.DailySettlement;
exec Pkg_FSS_Settlement.DailyBankingSummary;
exec Pkg_FSS_Settlement.DailyBankingSummary('06-JUN-2019');
exec Pkg_FSS_Settlement.TerminalUsageReport;
exec Pkg_FSS_Settlement.SendEmail;