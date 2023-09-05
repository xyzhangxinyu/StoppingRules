/*********************************
* File name:  RiskConsciousStoppingRule.sas 
* Purpose:    Select a set of case for stopping during the data collection 
* Programmer: Xinyu Zhang
* Date:       9/5/2023 
*********************************/

/* This example shows a risk-conscious stopping rule that is based on 1000 simulation draws of the predicted Y value and future costs for each case */
/* The stopping rule aims to minimize the mean sqaured error for a given budget */

/* Data requirement: long format (each row is one simulation draw per case) */

/* 
* Inputs: 
*  future_calls: predicted case-level costs (at the time point to implement the rule)
*  var1: a survey variable of interest for each case (missing data are imputed); this variable is standardized by z-score scaling
*  &budget: a budget level needs to be specified before implementing the rule
*/

/*
* Output:
* A data set that includs cases for stopping: 
*  drop_id - a set of selected cases for stopping
*/

/*
* Other variables to specify before implementing the rule: 
*  iteration: simulation number
*  &n: number of unresolved cases 
*  &cumcosts_obs: sunk cost (when implementing the rule)
*/

/* dataset "cvfun" contains only unresolved cases */
* obtain only future costs for each simulation draw;
data estcost (keep = iteration cumcalls_est);
set cvfun;
retain cumcalls_est;
by iteration; 
if first.iteration then cumcalls_est = 0;
cumcalls_est+future_calls;
if last.iteration then output;
run;

proc sort data = estcost; by iteration; run; 

data cvfun2;
merge cvfun (in = a) estcost;
by iteration;
if a;
run;

* obtain total costs for each simulation draw: sunk cost + future cost;
data cvfun3; 
set cvfun2;
cumcosts2 = &cumcosts_obs + cumcalls_est;
run;

proc sort data = cvfun3; by iteration; run; 

/*** 
* drop one case based on the multiplicative cost-error tradeoff 
***/
/* calculate the multiplicative cost-error tradeoff */
data cvfun4;
set cvfun3;
psi_hat = (cumcosts2 - future_calls) * ( (var1 / (&n-1))**2 + 1/(&n-1) );
remaining_cost = (cumcosts2 - future_calls) ;
estimated_var1 = ( (var1 / (&n-1))**2 + 1/(&n-1) ); 
run;

proc sort data = cvfun4; by iteration; run;

/* identify the upper bound of the multiplicative cost-error tradeoff */
proc rank data = cvfun4 out = CB_rk;
by  iteration;
var psi_hat;
ranks psi_hat_rank;
run;

proc sort data = CB_rk; by vsamplelineid iteration; run;

proc summary data = CB_rk ;       
by  vsamplelineid;
var psi_hat;    
output out = CB_rk2 (keep = vSampleLineId psi_hat_P10
psi_hat_P90) p10= p90= / autoname;
run;

proc sql;
create table psi_srh as
select iteration, max(psi_hat) as maxpsi, 
 min(psi_hat) as minpsi 
from CB_rk
group by iteration;
quit;

proc sql;
select max(minpsi) as maxmin, min(maxpsi) as minmax
from psi_srh;
quit;

proc sort data = CB_rk2; by psi_hat_P90; run;

* stop the case with the lowest upper bound;
data CB_rk3;
set CB_rk2;
if _N_ = 1;
run; 

* get ID for stopping;
data _null_;
set CB_rk3;
call symput('vsamplelineid', vsamplelineid);
run;

data cvfun4a;
set cvfun4;
if vsamplelineid =&vsamplelineid;
run;

* obtain the confidence bounds for the cost and the estimated mean sqaured error; 
* (determine the number of cases for stopping based on a specified constraint); 
proc sort data = cvfun4a; by remaining_cost; run;

data cvfun4c (keep = vsamplelineid remaining_cost_p10);
set cvfun4a;
if _n_ = 101; /* 10% of 1000 scenarios */
remaining_cost_p10 = remaining_cost;
run;

data cvfun4b (keep = vsamplelineid remaining_cost_p90);
set cvfun4a;
if _n_ = 901; /* 90% of 1000 scenarios */ 
remaining_cost_p90 = remaining_cost;
run;

proc sort data = cvfun4a; by estimated_var1; run;

data cvfun4d (keep = vsamplelineid estimated_var1_p10);
set cvfun4a;
if _n_ = 101; /* 10% of 1000 scenarios */
estimated_var1_p10 = estimated_var1;
run;

data cvfun4e (keep = vsamplelineid estimated_var1_p90);
set cvfun4a;
if _n_ = 901; /* 90% of 1000 scenarios */
estimated_var1_p90 = estimated_var1;
run;

data CB_rk3;
merge cvfun4c cvfun4b cvfun4e cvfun4d CB_rk3;
by vsamplelineid;
run;

data drop;
set CB_rk3;
order = 1;
run;

*;
%let nobs = %sysevalf(&n - 1); 

/* A function to stop cases in a sequential order */
%macro psiloop; 

%do i = 1 %to & nobs;  

data _NULL_; 
if 0 then set drop nobs=j; 
call symput('j',j); 
stop; 
run;

%put &j;

proc sort data = drop out = dropid (keep = vSampleLineId); 
by vSampleLineId; 
run; 

data cvfun4_drop cvfun4remain;
merge dropid (in = a) cvfun4 (in = b); 
by vSampleLineId;
if b and not a then output cvfun4remain;
else output cvfun4_drop; 
run;

proc sort data = cvfun4_drop; by iteration; run;

data cvfun4drop2 (keep = iteration sum_cost_drop p_var1_drop_sum);
set cvfun4_drop;
retain sum_cost_drop p_var1_drop_sum;
by iteration;
if first.iteration then  do; 
sum_cost_drop  = 0;
p_var1_drop_sum = 0;
end;
sum_cost_drop+future_calls;
p_var1_drop_sum + var1;
if last.iteration then output;
run; 

proc sort data = cvfun4drop2; by iteration; run; 
proc sort data = cvfun4remain; by iteration; run; 

data cvfun4remain;
merge cvfun4remain(in = a) cvfun4drop2;
by iteration;
if a;
run;

data cvfun4remain;
set cvfun4remain;
psi_hat = (cumcosts2 - sum_cost_drop - future_calls) * 
( ( (var1 + p_var1_drop_sum) / (&n-&j-1))**2 + 1/(&n-&j-1) );
remaining_cost = (cumcosts2 - sum_cost_drop - future_calls) ;
estimated_var1 = ( ( (var1 + p_var1_drop_sum) / (&n-&j-1))**2
+ 1/(&n-&j-1) );
run;

proc sort data = cvfun4remain; by iteration; run;

proc rank data = cvfun4remain out = CB_rk;
by  iteration;
var psi_hat;
ranks psi_hat_rank;
run;

proc sort data = CB_rk; by vsamplelineid iteration; run;

proc summary data = CB_rk ;       
by  vsamplelineid;
var psi_hat ;    
output out = CB_rk2 (keep = vSampleLineId psi_hat_P10 
psi_hat_P90) p10= p90= / autoname;
run;

proc sort data = CB_rk2; by psi_hat_P90; run;

data CB_rk3;
set CB_rk2;
if _N_ = 1;
run; 

data _null_;
set CB_rk3;
call symput('caseidtostop',vsamplelineid);
run;

data cvfun4a;
set cvfun4remain;
if vsamplelineid =&caseidtostop;
run;

proc sort data = cvfun4a; by remaining_cost; run;

data cvfun4c (keep = vsamplelineid remaining_cost_p10);
set cvfun4a;
if _n_ = 101; /* 10% of 1000 scenarios */
remaining_cost_p10 = remaining_cost;
run;

data cvfun4b (keep = vsamplelineid remaining_cost_p90);
set cvfun4a;
if _n_ = 901; /* 90% of 1000 scenarios */
remaining_cost_p90 = remaining_cost;
run;

proc sort data = cvfun4a; by estimated_var1; run;

data cvfun4d (keep = vsamplelineid estimated_var1_p10);
set cvfun4a;
if _n_ = 101; /* 10% of 1000 scenarios */
estimated_var1_p10 = estimated_var1;
run;

data cvfun4e (keep = vsamplelineid estimated_var1_p90);
set cvfun4a;
if _n_ = 901; /* 90% of 1000 scenarios */
estimated_var1_p90 = estimated_var1;
run;

data CB_rk3;
merge cvfun4c cvfun4b cvfun4e cvfun4d CB_rk3;
by vsamplelineid;
run;

data drop2;
set CB_rk3;
order = 1 + &j;
run;

data drop;
set drop2 drop;
run;

%end;

%mend;

%psiloop;

/* identify the set of cases for stopping based on the prespecified budget */
proc sort data = drop; by order ; run;	
data drop_id;	
set drop;	
if remaining_cost_p90 < &budget then do;	
output;	
stop;	
end;	
run;	
