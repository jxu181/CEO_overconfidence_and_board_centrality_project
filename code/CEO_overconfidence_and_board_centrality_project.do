clear
clear matrix
set memory 2000m
global path C:\Users\Polyu\Desktop\Projects\CEO_overconfidence_and_board_centrality_project

*****************************************Construct the CEO and executives sample*******************************************************
**prepare cik and gvkey identifier**
use $path\data\board_ex\cikgvkey, replace
rename fyear year
keep cik cusip year
replace cusip=substr(cusip, 1,8)
drop if cik=="" | cusip==""
duplicates drop cusip year, force //pure duplicates//
save $path\temp\cikgvkey2, replace



use $path\data\execu_comp\executive, clear
rename YEAR year
rename CUSIP cusip
merge m:1 cusip year using $path\temp\cikgvkey2, keepusing(cik)
drop if _merge==2
sort cusip year
by cusip: replace cik=cik[_n-1] if cik=="" & _merge==1
gsort cusip -year
by cusip: replace cik=cik[_n-1] if cik=="" & _merge==1
drop if cik==""
drop _merge
rename cusip CUSIP


drop if year<2008 | year>2018
replace CEOANN="CEO" if CEOANN!=""
format TITLEANN %20s
format CONAME %20s

foreach v of varlist SALARY BONUS OTHCOMP OTHANN RSTKGRNT OPTION_AWARDS LTIP{
replace `v'=0 if `v'==.
}
replace TDC1=SALARY+BONUS+OTHCOMP+OTHANN+RSTKGRNT+OPTION_AWARDS+LTIP if TDC1==.

//make sure each company-year has one CEO//
gen CEO=CEOANN
gsort CUSIP year -CEO
by CUSIP year: replace CEO=CEO[_n-1] if _n>1
gsort CUSIP year -TDC1
by CUSIP year: gen id=_n if CEO==""
replace CEOANN="CEO" if id==1 //regard highest TDC1 executive as CEO if the company-year has no CEO//
drop CEO id
//use the highest tdc1 CEO as CEO if the company-year has more than 1 CEO//
gsort CUSIP year CEOANN -TDC1
by CUSIP year CEOANN: gen id=_n if CEOANN=="CEO"
replace CEOANN="" if id!=1
drop id
keep if CEOANN=="CEO"
save $path\temp\CEOsample, replace

********************************************construct CEO overconfidence measure******************************************************************
use $path\data\CCMAnn, clear
drop if cusip==""
duplicates drop cusip fyear, force
gen CUSIP=substr(cusip,1,8)
rename fyear year
keep CUSIP year prcc_f
save $path\temp\prcc_f, replace

use $path\temp\CEOsample, clear
merge m:1 CUSIP year using $path\temp\prcc_f
keep if _merge==3
drop _merge
gen Confidence=(OPT_UNEX_EXER_EST_VAL/OPT_UNEX_EXER_NUM)/prcc_f
drop prcc_f

gen Overconfidence=.
forvalues i=2008/2018{
_pctile Confidence if year==`i' & Confidence!=., nq(5)
return list
replace Overconfidence=1 if Confidence>=r(r4) & year==`i' & Confidence!=.
}
replace Overconfidence=0 if Overconfidence==. & Confidence!=.
keep CUSIP year Overconfidence Confidence
save $path\temp\Overconfidence, replace

****************************calculate the network centrality****************************************************************************

use $path\data\board_ex\organizationsummary.dta, clear
//change annual report date to fiscal year//
gen year=year(annualreportdate) if month(annualreportdate)>=6
replace year=year(annualreportdate)-1 if year==.
duplicates drop boardid year directorid, force
rename cikcode cik
keep boardid cik directorid year
drop if year<2008 | year>2018
save $path\temp\board_director, replace

forvalues i=2008/2018{
use $path\temp\board_director, clear
keep if year==`i'
drop year cik
sort boardid directorid
save $path\temp\temp, replace
rename boardid lboardid
joinby directorid using $path\temp\temp
drop directorid
sort lboardid boardid
bysort lboardid boardid: gen id=_n
bysort lboardid boardid: egen value=max(id)
drop id
replace value=1 if lboardid==boardid
duplicates drop lboardid boardid, force
save $path\temp\boardnetwork`i', replace
}


forvalues i=2008/2018{
import excel  $path\temp\boardnetwork`i'-deg, firstrow  clear
rename ID boardid
gen year=`i'
save $path\temp\boardcentrality_deg`i', replace
}
forvalues i=2008/2017{
append using $path\temp\boardcentrality_deg`i'
}
sort year boardid
save $path\temp\boardcentrality_deg, replace

use $path\temp\board_director, clear
merge m:1 boardid year using $path\temp\boardcentrality_deg
drop _merge
drop if cik==""
drop directorid boardid
//change cik format and delete replications //
gen cik2=substr("0000000000", 1, 10-length(cik))+cik
drop cik
rename cik2 cik
duplicates drop cik year, force
save $path\temp\boardcentrality, replace

*********************CEO control variables**********************************
*In(CEOtenure)：The natural log of one plus the number of years that the CEO has been the CEO of the company。
*ln (CEO age)：The natural log of the CEO’s age.
*CEO bonus/salary：The ratio of the CEO’s bonus payment as ratio of his or her fixed salary.

use $path\temp\CEOsample, clear
gen CEOtenure=year-year(BECAMECEO)
sort CUSIP EXECID year
by CUSIP EXECID: gen id=_n
replace CEOtenure=id-1 if CEOtenure==. | CEOtenure<0
gen lnCEOtenure=ln(1+CEOtenure)
gen lnCEOage=ln(AGE)
gen bonus_salary=BONUS/SALARY
//construct CEO power measure//
gen CEOpower=0
replace CEOpower=1 if strmatch(TITLEANN, "*chairman*") | strmatch(TITLEANN, "*chmn*")
replace CEOpower=2 if (strmatch(TITLEANN, "*chairman*") | strmatch(TITLEANN, "*chmn*")) & (strmatch(TITLEANN, "*president*") |strmatch(TITLEANN, "*pres*"))
keep CUSIP year lnCEOtenure lnCEOage bonus_salary CEOpower
save $path\temp\CEOcontrols, replace


**********************Corporate control variables**********************************
*MTB:The firm’s market-to-book ratio, being its market value at the end of the fiscal year (CRSP/Compustat: prcc_f × csho) divided by its book assets (Compustat: at).
*Cash/assets:The firm’s cash holdings (Compustat: ch) divided by its book assets (Compustat: at). 
*R&D/sales:The firm’s R&D expenditure (Compustat: xrd) divided by its sales (Compustat: sale).
*CAPEX/assets:The firm’s capital expenditures (Compustat: capx) scaled by its assets (Compustat: at).
*CAPEX/sales:The firm’s capital expenditure (Compustat: capx) divided by its sales (Compustat: sale).
*Ln (assets):The natural log of the firm’s book assets (Compustat: at).
*Debt/assets:The firm’s long-term debt (Compustat: dltt) scaled by its assets (Compustat: at).
*Intangibles/assets:The firm’s intangible assets (Compustat: intan) scaled by its total book assets (Compustat: at).
*Inst%ownership：The percentage of the firm that institutional investors owns.

use $path\data\institution, clear
drop if cusip==""
sort cusip rdate mgrno
duplicates drop cusip rdate mgrno, force //note: pure replication of cusip and fyear//
bysort cusip rdate: egen InstS=sum(shares)
gen shrout=shrout1*1000000
gen InstP=InstS/shrout
duplicates drop cusip rdate, force
keep cusip rdate InstP
gen year=year(rdate)
collapse (mean) InstP, by(cusip year)
sort cusip year
rename cusip CUSIP
save $path\temp\InstP, replace


use $path\data\CCMAnn, clear
drop if cusip==""
duplicates drop cusip fyear, force
gen CUSIP=substr(cusip,1,8)
rename fyear year
egen id=group(cusip)
tsset id year
gen Cash_Assets=ch/at
gen Size=ln(csho*prcc_f)
gen Tobinq=(at-ceq+csho*prcc_f)/at
replace xrd=0 if xrd==.
gen RandD_Sales=xrd/sale
gen CAPEX_Sales=capx/sale
gen CAPEX=capx/l.at
gen LnAssets=ln(at)
gen Debt_Assets=dltt/at
gen Intangibles_Assets=intan/at
gen ROA=ib/at
gen ChangeROA=ROA-l.ROA
gen CF=(ib+dpc)/at
merge 1:1 CUSIP year using $path\temp\InstP
drop if _merge==2
drop _merge
replace InstP=0 if InstP==.
keep CUSIP year Cash_Assets RandD_Sales CAPEX CAPEX_Sales LnAssets Debt_Assets Intangibles_Assets InstP Tobinq ROA CF ChangeROA Size
save $path\temp\Firmcontrols, replace


*********************************prepare market control variables**********************************
*Stock return:The firm’s cumulative daily stock return over year t. The data is from CRSP. 
*Stock std dev:The firm’s standard deviation of daily stock returns over year t. The data is from CRSP.
*Prop No Trade Days:The proportion of days in year t on which there was no trade in the company’s stock.
use $path\data\CRSPdaily, clear
sort CUSIP date
gen year=year(date)
bysort CUSIP year: gen id=_n
bysort CUSIP year: egen max=max(id)
gen Notradepercentage=max/365
replace Notradepercentage=1-Notradepercentage
drop id max
gen lnret=ln(1+RET)
bysort CUSIP year: egen sumlnret=sum(lnret)
bysort CUSIP year: gen Stock_Return=exp(sumlnret)-1
bysort CUSIP year: egen Stock_stddev=sd(RET)
keep CUSIP year Stock_Return Stock_stddev Notradepercentage
duplicates drop CUSIP year, force
save $path\temp\Marketcontrols, replace



***********************Dependent variables******************************
**performance measures**
*MTB:The firm’s market-to-book ratio, being its market value at the end of the fiscal year (CRSP/Compustat: prcc_f × csho) divided by its book assets (Compustat: at).
*Ind adj MTB:The firm’s industry adjusted Tobin’s Q, defined as its Tobin’s Q less the average Tobin’s Q for all firms in its two-digit SIC industry and year.
*EBIT/assets:The firm’s EBIT (Compustat: ebit) scaled by its book assets (Compustat: at). 
*Ind adj EBIT/assets The firm’s EBIT/assets less the mean EBIT/assets for all companies in the firm’s two-digit SIC industry and year

use $path\data\CCMAnn, clear
drop if cusip==""
duplicates drop cusip fyear, force
gen CUSIP=substr(cusip,1,8)

rename fyear year
egen id=group(CUSIP)
tsset id year

gen CAPEX=capx/l.at
gen fCAPEX=f.CAPEX
gen ROA=ib/at
gen fROA=f.ROA
gen ChangeROA=ROA-l.ROA
gen fChangeROA=f.ChangeROA
gen Tobinq=(at-ceq+csho*prcc_f)/at
gen fTobinq=f.Tobinq

keep CUSIP year f* sic
order f*
save $path\temp\performance, replace



************************merge data********************************************
use $path\temp\CEOsample, clear
merge 1:1 CUSIP year using $path\temp\Overconfidence
drop if _merge==2
drop _merge

merge 1:1 cik year using $path\temp\boardcentrality
drop if _merge==2
drop _merge

merge 1:1 CUSIP year using $path\temp\CEOcontrols
drop _merge
merge 1:1 CUSIP year using $path\temp\Firmcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\Marketcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\performance
drop if _merge==2
drop _merge

gen sic2= substr(sic,1,2)
destring sic2, replace

gen OCxDegree=Overconfidence*Degree
gen OCxCF=Overconfidence*CF
gen OCxCFxDegree=Overconfidence*CF*Degree

gen ConfidencexDegree=Confidence*Degree
gen ConfidencexCF=Confidence*CF
gen ConfidencexCFxDegree=Confidence*CF*Degree

gen DegreexCF=Degree*CF
save $path\temp\reg, replace

use $path\temp\reg, clear
global CEOcontrols CEOpower lnCEOtenure lnCEOage bonus_salary 
global Marketcontrols Tobinq Stock_Return Stock_stddev InstP Notradepercentage

global Firmcontrols Size Debt_Assets Intangibles_Assets CAPEX RandD_Sales LnAssets
quietly xi: reg fCAPEX Overconfidence Degree CF DegreexCF OCxDegree OCxCF OCxCFxDegree $CEOcontrols $Firmcontrols $Marketcontrols  i.sic2 i.year , cluster(CUSIP)
est store m1
quietly xi: reg fCAPEX Confidence Degree CF DegreexCF ConfidencexDegree ConfidencexCF ConfidencexCFxDegree $CEOcontrols $Firmcontrols $Marketcontrols  i.sic2 i.year , cluster(CUSIP)
est store m2
esttab m1 m2, varwidth(25) scalar(r2 r2_a N F) compress star(* 0.1 ** 0.05 *** 0.01) b(%6.3f) t(%6.3f) drop(_Iyear_* _Isic2_*)


global Firmcontrols Size Debt_Assets RandD_Sales Intangibles_Assets CAPEX ChangeROA LnAssets
quietly xi: reg fChangeROA Overconfidence Degree OCxDegree  $CEOcontrols $Firmcontrols $Marketcontrols  i.sic2 i.year, cluster(CUSIP)
est store m1
quietly xi: reg fChangeROA Confidence Degree ConfidencexDegree  $CEOcontrols $Firmcontrols $Marketcontrols  i.sic2 i.year, cluster(CUSIP)
est store m2

esttab m1 m2, varwidth(25) scalar(r2 r2_a N F) compress star(* 0.1 ** 0.05 *** 0.01) b(%6.3f) t(%6.3f) drop(_Iyear_* _Isic2_*)



*******************************prepare MA data****************************************
forvalues i=2000/2019{
import excel  $path\data\MA\MA`i', firstrow  clear
save $path\data\MA\MA`i', replace
}

use $path\data\MA\MA2000, clear
forvalues i=2001/2019{
append using $path\data\MA\MA`i'
}
save $path\data\MA\MAall, replace


//Announced Acquisition//
use $path\data\MA\MAall, clear
rename AcquirorCUSIP CUSIP
drop if CUSIP==""
gen year=year(DateAnnounced)
drop if year<2008 | year>2019
keep CUSIP year
duplicates drop CUSIP year, force
sort CUSIP year
save $path\temp\MA_announce, replace

use $path\temp\CEOsample, clear
merge 1:1 CUSIP year using $path\temp\Overconfidence
drop if _merge==2
drop _merge

merge 1:1 cik year using $path\temp\boardcentrality
drop if _merge==2
drop _merge

merge 1:1 CUSIP year using $path\temp\CEOcontrols
drop _merge
merge 1:1 CUSIP year using $path\temp\Firmcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\Marketcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\performance
drop if _merge==2
drop _merge

replace CUSIP=substr(CUSIP,1,6)
duplicates drop CUSIP year, force

replace year=year+1
merge 1:1 CUSIP year using $path\temp\MA_announce
drop if _merge==2
gen ANN=1 if _merge==3
replace ANN=0 if ANN==.
drop _merge
gen sic2= substr(sic,1,2)
destring sic2, replace

gen OCxDegree=Overconfidence*Degree
gen OCxCF=Overconfidence*CF
gen OCxCFxDegree=Overconfidence*CF*Degree

gen ConfidencexDegree=Confidence*Degree
gen ConfidencexCF=Confidence*CF
gen ConfidencexCFxDegree=Confidence*CF*Degree

gen DegreexCF=Degree*CF

global CEOcontrols CEOpower lnCEOtenure lnCEOage bonus_salary 
global Marketcontrols Tobinq Stock_Return Stock_stddev InstP Notradepercentage

global Firmcontrols Debt_Assets Intangibles_Assets CAPEX RandD_Sales LnAssets Size
quietly xi: logit ANN Overconfidence Degree CF OCxDegree OCxCF DegreexCF OCxCFxDegree $CEOcontrols $Firmcontrols $Marketcontrols i.sic2 i.year , cluster(CUSIP)
est store m1
quietly xi: logit ANN Confidence Degree CF ConfidencexDegree DegreexCF ConfidencexCFxDegree $CEOcontrols $Firmcontrols $Marketcontrols i.sic2 i.year , cluster(CUSIP)
est store m2
esttab m1 m2, varwidth(25) scalar(r2 r2_a N F) compress star(* 0.1 ** 0.05 *** 0.01) b(%6.3f) t(%6.3f) drop(_Iyear_* _Isic2_*)






//Diversifying Acquisition//
use $path\data\MA\MAall, clear
drop if TargetName==""
bysort TargetName: gen id=_n
bysort TargetName: egen max=max(id)
drop if max==1
sort TargetName DateAnnounced


sort TargetCUSIP AcquirorCUSIP DateAnnounced






rename AcquirorCUSIP CUSIP
gen year=year(DateAnnounced)
drop if year<2008 | year>2019
drop if CUSIP==""
gen Tenderoffer=1 if TenderOffer=="Yes"
replace Tenderoffer=0 if Tenderoffer==.
gen Diversifying=1 if substr(AcquirorSIC,1,2)!=substr(TargetSIC,1,2)
replace Diversifying=0 if Diversifying==.
keep CUSIP year Tenderoffer Diversifying
save $path\temp\DiversifyingMA, replace

use $path\temp\CEOsample, clear
merge 1:1 CUSIP year using $path\temp\Overconfidence
drop if _merge==2
drop _merge

merge 1:1 cik year using $path\temp\boardcentrality
drop if _merge==2
drop _merge

merge 1:1 CUSIP year using $path\temp\CEOcontrols
drop _merge
merge 1:1 CUSIP year using $path\temp\Firmcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\Marketcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\performance
drop if _merge==2
drop _merge

replace CUSIP=substr(CUSIP,1,6)
duplicates drop CUSIP year, force

replace year=year+1
merge 1:m CUSIP year using $path\temp\DiversifyingMA
keep if _merge==3
drop _merge


gen sic2= substr(sic,1,2)
destring sic2, replace

gen OCxDegree=Overconfidence*Degree
gen ConfidencexDegree=Confidence*Degree
gen DegreexCF=Degree*CF

global CEOcontrols CEOpower lnCEOtenure lnCEOage bonus_salary 
global Marketcontrols Tobinq Stock_Return Stock_stddev InstP Notradepercentage

global Firmcontrols Debt_Assets Intangibles_Assets CAPEX RandD_Sales LnAssets CF


quietly xi: logit Diversifying Overconfidence $CEOcontrols $Firmcontrols $Marketcontrols i.sic2 i.year , cluster(CUSIP)
est store m1
quietly xi: logit Diversifying Confidence $CEOcontrols $Firmcontrols $Marketcontrols i.sic2 i.year , cluster(CUSIP)
est store m2
esttab m1 m2, varwidth(25) scalar(r2 r2_a N F) compress star(* 0.1 ** 0.05 *** 0.01) b(%6.3f) t(%6.3f) drop(_Iyear_* _Isic2_*)




quietly xi: logit Diversifying Overconfidence Degree OCxDegree i.sic2 i.year , cluster(CUSIP)
est store m1
quietly xi: logit Diversifying Confidence Degree ConfidencexDegree i.sic2 i.year , cluster(CUSIP)
est store m2
esttab m1 m2, varwidth(25) scalar(r2 r2_a N F) compress star(* 0.1 ** 0.05 *** 0.01) b(%6.3f) t(%6.3f) drop(_Iyear_* _Isic2_*)


//Announced return//
use $path\data\CRSPdaily, clear
gen year=year(date)
replace CUSIP=substr(CUSIP,1,6)
duplicates drop CUSIP date, force
egen id=group(CUSIP)
tsset id date
tsfill

foreach v of varlist RET vwretd ewretd sprtrn {
replace `v'=0 if CUSIP=="" & year==.
}
replace CUSIP=CUSIP[_n-1] if id==id[_n-1]
*gsort id -date
*replace CUSIP=CUSIP[_n-1] if id==id[_n-1]
gen abret=RET-vwretd
gen lnabret=ln(1+abret)
sort id date
gen sumlnabret=lnabret+f.lnabret+l.lnabret
gen CAR1_1=exp(sumlnabret)-1
save $path\temp\CRSPAnnret, replace


use $path\data\MA\MAall, clear
gen year=year(DateAnnounced)
keep if SharesOwned>=51 | sought>=51
drop if SharesOwned-sought>51

rename AcquirorCUSIP CUSIP
drop if CUSIP==""
gen Tenderoffer=1 if TenderOffer=="Yes"
replace Tenderoffer=0 if Tenderoffer==.
gen Diversifying=1 if substr(AcquirorSIC,1,2)!=substr(TargetSIC,1,2)
replace Diversifying=0 if Diversifying==.
gen date=DateAnnounced

gsort CUSIP date -Value_Transaction
by CUSIP date: gen id=_n
keep if id==1
drop id

merge 1:1 CUSIP date using $path\temp\CRSPAnnret
keep if _merge==3
drop _merge
save $path\temp\MAAnnret, replace








use $path\temp\CEOsample, clear
merge 1:1 CUSIP year using $path\temp\Overconfidence
drop if _merge==2
drop _merge

merge 1:1 cik year using $path\temp\boardcentrality
drop if _merge==2
drop _merge

merge 1:1 CUSIP year using $path\temp\CEOcontrols
drop _merge
merge 1:1 CUSIP year using $path\temp\Firmcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\Marketcontrols
drop if _merge==2
drop _merge
merge 1:1 CUSIP year using $path\temp\performance
drop if _merge==2
drop _merge

replace CUSIP=substr(CUSIP,1,6)
duplicates drop CUSIP year, force

replace year=year+1
merge 1:m CUSIP year using $path\temp\MAAnnret
keep if _merge==3
drop _merge


gen sic2= substr(sic,1,2)
destring sic2, replace

gen OCxDegree=Overconfidence*Degree
gen ConfidencexDegree=Confidence*Degree

global CEOcontrols CEOpower lnCEOtenure lnCEOage bonus_salary 
global Marketcontrols Tobinq Stock_Return Stock_stddev InstP Notradepercentage

global Firmcontrols Debt_Assets Intangibles_Assets CAPEX RandD_Sales LnAssets CF

winsor CAR1_1, gen(wCAR1_1) p(0.01)
quietly xi: reg wCAR1_1 Overconfidence i.sic2 i.year , cluster(CUSIP)
est store m1
quietly xi: reg wCAR1_1 Confidence i.sic2 i.year , cluster(CUSIP)
est store m2
esttab m1 m2, varwidth(25) scalar(r2 r2_a N F) compress star(* 0.1 ** 0.05 *** 0.01) b(%6.3f) t(%6.3f) drop(_Iyear_* _Isic2_*)





help shell
shell git init
dir .git/


























