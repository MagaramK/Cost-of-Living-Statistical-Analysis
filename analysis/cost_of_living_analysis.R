# Global Cost-of-Living Statistical Analysis
library(dplyr)
library(ggplot2)

# 1. Importing and cleaning data
data <- read.csv("data/Cost_of_Living_Index_2024.csv", check.names = TRUE)
names(data)[names(data)=="Cost.of.Living.Index"] <- "Cost_of_Living_Index"
names(data)[names(data)=="GNI.per.Capita"] <- "GNI_per_Capita"
data <- data %>% mutate(
  Cost_of_Living_Index=as.numeric(Cost_of_Living_Index),
  GNI_per_Capita=as.numeric(gsub(",","",GNI_per_Capita))
)
N <- nrow(data)
population_mean <- mean(data$Cost_of_Living_Index)
population_variance <- var(data$Cost_of_Living_Index)
cat("Population size:",N,"\nPopulation mean:",population_mean,
    "\nPopulation variance:",population_variance,"\n\n")

# 2. Determining the total sample size
alpha <- 0.20
error_bound <- 1
n0 <- qnorm(1-alpha/2)^2*population_variance/error_bound^2
n <- round(n0/(1+n0/N))
cat("Total sample size:",n,"\n\n")

# 3. Performing simple random sampling without replacement (SRSWOR)
set.seed(3430)
srs_index <- sample(seq_len(N),n,replace=FALSE)
srs_sample <- data[srs_index,]
srs_mean <- mean(srs_sample$Cost_of_Living_Index)
srs_variance <- (1-n/N)*var(srs_sample$Cost_of_Living_Index)/n

# 4. Creating GNI-based income strata
stratified_data <- data %>% mutate(Income_Group=case_when(
 GNI_per_Capita>=0 & GNI_per_Capita<=4515 ~ "Lower Middle Income",
 GNI_per_Capita>=4516 & GNI_per_Capita<=14005 ~ "Upper Middle Income",
 GNI_per_Capita>=14006 ~ "High Income",
 TRUE ~ NA_character_))
strata <- stratified_data %>% group_by(Income_Group) %>% summarise(
 N_h=n(),W_h=N_h/N,S_h=sd(Cost_of_Living_Index),.groups="drop")

# 5. Adjusting rounded allocations to match the total sample size
allocate_integer_samples <- function(raw_allocation,total_n,capacity){
 allocation <- floor(raw_allocation); remainder <- total_n-sum(allocation)
 if(remainder>0){fractions<-raw_allocation-floor(raw_allocation)
  for(i in order(fractions,decreasing=TRUE)){if(remainder==0) break
   if(allocation[i]<capacity[i]){allocation[i]<-allocation[i]+1;remainder<-remainder-1}}}
 allocation}

# 6. Drawing stratified samples using assigned sample sizes
draw_stratified_sample <- function(full_data,allocation_table,seed){
 set.seed(seed)
 bind_rows(lapply(seq_len(nrow(allocation_table)),function(i){
  group_name<-allocation_table$Income_Group[i]; n_group<-allocation_table$n_h[i]
  group_data<-full_data %>% filter(Income_Group==group_name)
  group_data[sample(seq_len(nrow(group_data)),n_group,replace=FALSE),]}))}

# 7. Calculating stratified estimates
calculate_stratified_estimates <- function(sample_data,allocation_table){
 sample_stats<-sample_data %>% group_by(Income_Group) %>% summarise(
  sample_mean=mean(Cost_of_Living_Index),sample_variance=var(Cost_of_Living_Index),.groups="drop")
 results<-allocation_table %>% left_join(sample_stats,by="Income_Group")
 mean_estimate<-sum(results$W_h*results$sample_mean)
 variance_estimate<-sum(results$W_h^2*(1/results$n_h-1/results$N_h)*results$sample_variance)
 list(details=results,mean=mean_estimate,variance=variance_estimate)}

# 8. Calculating proportional allocation
proportional<-strata %>% mutate(raw_n_h=n*N_h/N)
proportional$n_h<-allocate_integer_samples(proportional$raw_n_h,n,proportional$N_h)
proportional_sample<-draw_stratified_sample(stratified_data,proportional,3430)
proportional_results<-calculate_stratified_estimates(proportional_sample,proportional)

# 9. Calculating Neyman allocation
neyman<-strata %>% mutate(raw_n_h=n*(N_h*S_h)/sum(N_h*S_h))
neyman$n_h<-allocate_integer_samples(neyman$raw_n_h,n,neyman$N_h)
neyman_sample<-draw_stratified_sample(stratified_data,neyman,3430)
neyman_results<-calculate_stratified_estimates(neyman_sample,neyman)

# 10. Comparing sampling methods
comparison<-data.frame(
 Method=c("SRSWOR","Proportional Allocation","Neyman Allocation"),
 Mean_Estimate=c(srs_mean,proportional_results$mean,neyman_results$mean),
 Variance_Estimate=c(srs_variance,proportional_results$variance,neyman_results$variance))
print(comparison)

# 11. Visualizing and saving results
p1<-ggplot(stratified_data,aes(Income_Group,Cost_of_Living_Index))+geom_boxplot()+
 labs(title="Cost of Living Index by Income Group",x="Income Group",y="Cost of Living Index")+theme_minimal()
p2<-ggplot(stratified_data,aes(GNI_per_Capita,Cost_of_Living_Index,shape=Income_Group))+geom_point(alpha=.75)+
 labs(title="Cost of Living Index vs. GNI per Capita",x="GNI per Capita",y="Cost of Living Index",shape="Income Group")+theme_minimal()
p3<-ggplot(comparison,aes(reorder(Method,Variance_Estimate),Variance_Estimate))+geom_col()+coord_flip()+
 labs(title="Estimated Variance by Sampling Method",x="Sampling Method",y="Estimated Variance")+theme_minimal()
ggsave("figures/cost_of_living_by_income_group.png",p1,width=8,height=5,dpi=300)
ggsave("figures/cost_of_living_vs_gni.png",p2,width=8,height=5,dpi=300)
ggsave("figures/sampling_variance_comparison.png",p3,width=8,height=5,dpi=300)
