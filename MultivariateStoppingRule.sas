/*********************************
* File name:  MultivariateStoppingRule.sas 
* Purpose:    Stop a set of cases aimed at optimizing the cost-error tradeoff
* Programmer: Xinyu Zhang
* Date:       9/5/2023 
*********************************/

/* The stopping rule aims to optimize the quality of two survey estimates and the cost of data collection */

/* Data requirement: datasets are at the case level */

/* 
* Inputs: 
*  futurecosts: predicted case-level costs (at the time point to implement the rule)
*  var1: a survey variable of interest for each case (missing data are imputed); this variable is standardized by z-score scaling
*  var2: another survey variable of interest for each case (missing data are imputed); this variable is standardized by z-score scaling
*/

/*
* Output:
* A data set that includs cases for stopping: 
*  casestostop - a set of selected cases for stopping
*/

/*
* Other variables to specify before implementing the rule: 
*  &n: number of unresolved cases 
*  &cumcosts: predicted total costs
*/

* initial value for the data quality component before stopping cases;
%let var_1_hat = %sysevalf(1 / &n * 1); 
* number of key estimates;
%let k = 2; 
* initial value before stopping cases;
%let psi_0 = %sysevalf((&cumcosts) / &n); 

/* select the case with the lowest value of the multiplicative cost-error tradeoff */
data cv2;
set cv;
psi = 1/&k * (&cumcosts - futurecosts) * 
( (var1 / (&n-1))**2 + 1/(&n-1) ) + 
1/&k * (&cumcosts - futurecosts) * 
( (var2/ (&n-1))**2 + 1/(&n-1) ) ;
run;

proc sort data = cv2; by psi; run;

data cv2_dropped cv2; 
set cv2; 
if _N_ = 1 then output cv2_dropped;
else output cv2; 
run;

%let nobs = %sysevalf(&n - 1); 

/* A function to stop cases in a sequential order */
%macro psiloop2; 

%do i = 1 %to &nobs;  

proc summary data = cv2_dropped;
var futurecosts var1 var2;
output out = cv2_totals sum = ;
run;

data _null_;
set cv2_totals;
call symput('sum_cost_drop', futurecosts);
call symput('sum_var1_drop', var1);
call symput('sum_var2_drop', var2);
run;

data _NULL_; 
if 0 then set cv2_dropped nobs=j;  
call symput('j',j); 
stop; 
run;

data cv2;
set cv2;
psi = 1/&k * (&cumcosts - &sum_cost_drop - futurecosts) * ( ( (&sum_var1_drop + var1) / (&n - &j -1) )**2 + 1/(&n - &j - 1) ) + 1/&k * (&cumcosts - &sum_cost_drop - futurecosts) * ( ( (&sum_var2_drop + var2) / (&n - &j -1) )**2 + 1/(&n - &j - 1) ) ;
run;

proc sort data = cv2; by psi; run;

/* select the case with the lowest psi */
data cv2_dropped2 cv2; 
set cv2; 
if _N_ = 1 then output cv2_dropped2;
else output cv2; 
run;

data cv2_dropped;
set cv2_dropped cv2_dropped2;
run;

%end;

%mend;

%psiloop2;

/* identify the set of cases for stopping */
* identify the case with the lowest value of the multiplicative tradeoff, and stop that case and any cases stopped before;
data cv2_dropped2;
  set cv2_dropped;
  id = _N_;  
run;

proc sort data = cv2_dropped2 out = cv2_dropped3; by psi; run;

data psimin; 
set cv2_dropped3; 
if _N_ = 1 and &psi_0 > psi; 
run;

data _null_;
set psimin;
call symput('id_psi_min', id);
run;

data casestostop;
set cv2_dropped3;
if id <= &id_psi_min;
run;
