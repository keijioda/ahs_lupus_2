
# AHS-2 lupus study 2

# Required packages
pacs <- c("tidyverse", "tableone", "emmeans")
sapply(pacs, require, character.only = TRUE)

# Function to search variables
search_var <- function(df, pattern, ...) {
  loc <- grep(pattern, names(df), ...)
  if (length(loc) == 0) warning("There are no such variables")
  else return(data.frame(loc = loc, varname = names(df)[loc]))
}

# Read data: n = 93,467 and 111 variables
filepath <- "./data/lupus-initial-dataset-v1-2022-04-25.csv"
lupus0  <- read_csv(filepath)
dim(lupus0)
names(lupus0)
n_distinct(lupus0$analysisid)

# Include non-Hispanic White or Black
# Exclude age < 30
# Exclude missing gender, diet pattern, education, smoking and BMI
# Exclude extreme kcal <500 or >4500
lupus <- lupus0 %>%
  mutate(
    age = ifelse(age < 30, NA, age),
    agecat = cut(age, breaks = c(0, 40, 60, Inf), right = FALSE),
    agecat = factor(agecat, labels = c("30-39", "40-59", ">=60")),
    sex = factor(sex, labels = c("Female", "Male")),
    black = case_when(
      ethyou == "01" ~ 0,
      ethyou %in% c("02", "03", "04", "05", "39", "40", "63", "74", "77", "96") ~ 1),
    black = factor(black, labels = c("White", "Black")),
    smkcat  = case_when(
      smokenow == 1 ~ 3,
      smoke > 1 & is.na(smokenow) ~ 2,
      smoke == 1 ~ 1
    ),
    smkcat  = factor(smkcat, labels = c("Never", "Past", "Current")),
    smkever = factor(smkcat, labels = c("Never", "Ever", "Ever")),
    educat3 = cut(educyou, breaks = c(0, 3, 6, 9)),
    educat3 = factor(educat3, labels = c("HS or less", "Some college", "Col grad")),
    # take_vd = ifelse(!is.na(vitd) & vitd == 2, 1, 0),
    # take_vd = factor(take_vd, labels = c("No", "Yes")),
    take_fo = ifelse(!is.na(fishoil) & fishoil == 2, 1, 0),
    take_fo = factor(take_fo, labels = c("No", "Yes")),
    bmicat  = cut(bmi, breaks = c(0, 25, 30, Inf), right = FALSE),
    bmicat  = factor(bmicat, labels = c("Normal", "Overweight", "Obese")),
    vegstat = factor(vege_group_gen_bl, levels = c("vegan", "lacto", "pesco", "semi", "nonveg")),
    vegstat3 = vegstat,
    prev_sle = ifelse(!is.na(sle) & sle == 2, 1, 0),
    prev_sle = factor(prev_sle, labels = c("No", "Yes"))) %>% 
  drop_na(sex, age, black, vege_group_gen_bl, smkever, educat3, bmi) %>% 
  filter(kcal >= 500 & kcal <= 4500)

levels(lupus$vegstat) <- c("Vegans", "Lacto-ovo", "Pesco", "Semi", "Non-veg")
levels(lupus$vegstat3) <- c("Vegetarians", "Vegetarians", "Pesco", "Non-veg", "Non-veg")

# Females only
lupus_f <- lupus %>% filter(sex == "Female")
dim(lupus_f)

# Yields n = 77,795 and n.cases = 237
dim(lupus)
lupus %>% count(prev_sle) %>% mutate(pct = n / sum(n) * 100)

# Nutrients
names(lupus)

# Omega-3: n3pfa (18:3, 18:4, 20:5, 22:5, 22:6)
# ALA    : p183diet, p183supp
# SDA    : p184diet, p184supp
# EPA    : p205diet, p205supp
# DPA    : p225diet, p225supp
# DHA    : p226diet, p226supp

lupus %>% 
  select(p183, p184, p205, p225, p226) %>% 
  summary()

# Percent of zero intake
lupus %>% 
  select(p183, p184, p205, p225, p226) %>% 
  pivot_longer(p183:p226, names_to = "fa", values_to = "value") %>% 
  mutate(zeros = ifelse(value == 0, 1, 0)) %>% 
  group_by(fa) %>% 
  summarize(pct_zero = mean(zeros) * 100)

lupus %>% 
  select(p183diet, p184diet, p205diet, p225diet, p226diet) %>% 
  summary()

lupus %>% 
  select(p183supp, p184supp, p205supp, p225supp, p226supp) %>% 
  summary()

lupus %>% 
  select(p183, p184, p205, p225, p226) %>% 
  pivot_longer(p183:p226, names_to = "fa", values_to = "value") %>% 
  # mutate(value = log(value + 1)) %>% 
  ggplot(aes(x = value)) +
  geom_histogram(bins = 20) +
  facet_grid(~ fa, scales = "free")

# Energy-adjustment
# Energy-adjust with zero partition
# By default, variables are log-transformed (excluding zeros)
kcal_adjust <- function(var, kcal, log=TRUE){
  if (missing(var))
    stop("Need to specify variable for energy-adjustment.")
  if (missing(kcal))
    stop("Need to specify kcal intake.")
  df <- data.frame(y = var, ea_y = var, kcal = kcal)
  count_negative <- sum(df$y < 0, na.rm=TRUE)
  if (count_negative > 0)
    warning("There are negative values in variable.")
  if(log) df$y[df$y > 0 & !is.na(df$y)] <- log(df$y[df$y > 0 & !is.na(df$y)])
  mod <- lm(y ~ kcal, data=df[df$y != 0, ])
  if(log){
    ea <- exp(resid(mod) + mean(df$y[df$y != 0], na.rm=TRUE))
    df$ea_y[!is.na(df$y) & df$y != 0] <- ea
  }
  else{
    ea <- resid(mod) + mean(df$y[df$y != 0], na.rm=TRUE)
    df$ea_y[!is.na(df$y) & df$y != 0] <- ea
  }
  return(df$ea_y)
}

# Create new variables
o3_vars         <- c("p183", "p184", "p205", "p225", "p226")
o3_diet_vars    <- paste0(o3_vars, "diet")
o3_supp_vars    <- paste0(o3_vars, "supp")

o3_vars_ea      <- paste0(o3_vars, "_ea")
o3_diet_vars_ea <- paste0(o3_diet_vars, "_ea")

# Energy-adjust only dietary component (not supplement)
lupus[o3_diet_vars_ea] <- lapply(lupus[o3_diet_vars], kcal_adjust, kcal = lupus$kcal)

# Add energy-adjusted dietary intake and supplement
calc_total_ea <- function(var) rowSums(lupus[c(paste0(var, "diet_ea"), paste0(var, "supp"))])
lupus[o3_vars_ea] <- lapply(o3_vars, calc_total_ea)

# Sum all omega-3 fatty acids energy-adjusted values
lupus$n3pfa_ea <- rowSums(lupus[o3_vars_ea])
lupus$p205p226_ea <- rowSums(lupus[c("p205_ea", "p226_ea")])

# How did she define omega-6?

# Descriptive table
table_vars <- c("age", "agecat", "black", "sex", "smkever", "educat3", "vegstat3", "take_fo", "bmi", "bmicat")
lupus %>% CreateTableOne(table_vars, strata = "prev_sle", data = .) %>%
  print(showAllLevels = TRUE, pDigits = 4)

table_vars <- c("p183_ea", "p205p226_ea", "n3pfa_ea")
lupus %>% CreateTableOne(table_vars, strata = "prev_sle", data = .) %>%
  print(showAllLevels = TRUE, pDigits = 4, nonnormal = table_vars)

# Logistic regression

# Change references
lupus_md <- lupus %>% 
  mutate(kcal100 = kcal / 100)
lupus_md$vegstat3 <- relevel(lupus_md$vegstat3, ref = "Non-veg")
lupus_md$educat3 <- relevel(lupus_md$educat3, ref = "Col grad")
lupus_md$agecat <- relevel(lupus_md$agecat, ref = ">=60")

# Function to display OR with 95% Wald CI
or_out <- function(glm){
  orci <- confint.default(glm)
  out <- data.frame(OR = exp(coef(glm)), lwr = exp(orci)[, 1], upr = exp(orci)[, 2])
  rownames(out) <- rownames(orci)
  out %>% slice(-1)
}

RHS <- c("agecat", "black", "sex")
fm <- formula(paste("prev_sle ~", paste0(RHS, collapse = " + ")))
m1 <- glm(fm, data = lupus_md, family = "binomial")
m2 <- update(m1, . ~ . + vegstat3)
m3 <- update(m1, . ~ . + vegstat3 + educat3)
m4 <- update(m1, . ~ . + vegstat3 + educat3 + smkever)
m5a <- update(m1, . ~ . + vegstat3 + educat3 + smkever + bmicat)
m5b <- update(m1, . ~ . + vegstat3 + educat3 + smkever + kcal100)

models <- list(m1, m2, m3, m4, m5a, m5b)
ci <- list(exp(confint.default(m1)), 
           exp(confint.default(m2)), 
           exp(confint.default(m3)), 
           exp(confint.default(m4)), 
           exp(confint.default(m5a)), 
           exp(confint.default(m5b)))
var_labels <- c("Age.: 30-39", 
                "Age.: 40-59", 
                "Race: Black", 
                "Sex.: Male", 
                "Diet: Vegetarians", 
                "Diet: Pesco veg", 
                "Educ: HS or less",
                "Educ: Some college",
                "Smkg: Ever", 
                "BMI.: Overweight",
                "BMI.: Obese",
                "Kcal / 100")
stargazer::stargazer(models, 
                     type = "text", 
                     digits = 2,
                     dep.var.caption = "",
                     dep.var.labels = "Outcome: Prevalent SLE",
                     model.numbers = FALSE,
                     column.labels = c("Model 1", "Model 2", "Model 3", "Model 4", "Model 5a", "Model 5b"),
                     covariate.labels = var_labels,
                     apply.coef = exp, 
                     ci.custom = ci, 
                     star.cutoffs = NA, 
                     omit = "Constant", 
                     omit.stat = c("aic", "ll"),
                     omit.table.layout = "n")

# Trend p-values
getLastPval <- function(x) broom::tidy(x) %>% select(p.value) %>% slice(nrow(.))

Mod1 <- Mod2 <- Mod3 <- Mod4 <- Mod5a <- Mod5b <- list()

# Model 1, age
Mod1["agecat"] <- update(m1, .~. - agecat + as.numeric(agecat)) %>% 
  getLastPval()

# Model 2, age
Mod2["agecat"] <- update(m2, .~. - agecat + as.numeric(agecat)) %>% 
  getLastPval()

# Model 2, vegstat3
Mod2["vegstat3"] <- update(m2, .~. - vegstat3 + as.numeric(vegstat3), data = lupus) %>% 
  getLastPval()

# Model 3, age
Mod3["agecat"] <- update(m3, .~. - agecat + as.numeric(agecat)) %>% 
  getLastPval()

# Model 3, vegstat3
Mod3["vegstat3"] <- update(m3, .~. - vegstat3 + as.numeric(vegstat3), data = lupus) %>% 
  getLastPval()

# Model 3, educat3
Mod3["educat3"] <- update(m3, .~. - educat3 + as.numeric(educat3), data = lupus) %>% 
  getLastPval()

# Model 4, age
Mod4["agecat"] <- update(m4, .~. - agecat + as.numeric(agecat)) %>% 
  getLastPval()

# Model 4, vegstat3
Mod4["vegstat3"] <- update(m4, .~. - vegstat3 + as.numeric(vegstat3), data = lupus) %>% 
  getLastPval()

# Model 4, educat3
Mod4["educat3"] <- update(m4, .~. - educat3 + as.numeric(educat3), data = lupus) %>% 
  getLastPval()

# Model 5a, age
Mod5a["agecat"] <- update(m5a, .~. - agecat + as.numeric(agecat)) %>% 
  getLastPval()

# Model 5a, vegstat3
Mod5a["vegstat3"] <- update(m5a, .~. - vegstat3 + as.numeric(vegstat3), data = lupus) %>% 
  getLastPval()

# Model 5a, educat3
Mod5a["educat3"] <- update(m5a, .~. - educat3 + as.numeric(educat3), data = lupus) %>% 
  getLastPval()

# Model 5a, BMI
Mod5a["bmicat"] <- update(m5a, .~. - bmicat + as.numeric(bmicat)) %>% 
  getLastPval()

# Model 5b, age
Mod5b["agecat"] <- update(m5b, .~. - agecat + as.numeric(agecat)) %>% 
  getLastPval()

# Model 5b, vegstat3
Mod5b["vegstat3"] <- lupus %>% 
  mutate(kcal100 = kcal / 100) %>% 
  update(m5b, .~. - vegstat3 + as.numeric(vegstat3), data = .) %>% 
  getLastPval()

# Model 5b, educat3
Mod5b["educat3"] <- lupus %>% 
  mutate(kcal100 = kcal / 100) %>% 
  update(m5b, .~. - educat3 + as.numeric(educat3), data = .) %>% 
  getLastPval()

all_trend <- list(Mod1, Mod2, Mod3, Mod4, Mod5a, Mod5b)
names(all_trend) <- c("Model 1", "Model 2", "Model 3", "Model 4", "Model 5a", "Model 5b")
all_trend %>% 
  map(as.data.frame) %>% 
  map(\(x) round(x, 4))

# Year of diagnosis and start of supplements
lupus %>% select(sley) %>% table()
lupus %>% select(vitdy) %>% table()

lupus %>% 
  mutate(sley = ifelse(sley == 0, NA, sley),
         sley = factor(sley, labels = c("<5 yrs", "5-9 yrs", "10-14 yrs", "15-19 yrs", "20+ yrs")),
         vitdy = factor(vitdy, labels = c("0-4 yrs", "0-4 yrs", "5-9 yrs", "10+ yrs"))) %>% 
  select(sley, vitdy) %>% table()

lupus %>% 
  mutate(sley = ifelse(sley == 0, NA, sley),
         sley = factor(sley, labels = c("<5 yrs", "5-9 yrs", "10-14 yrs", "15-19 yrs", "20+ yrs")),
         fishoily = factor(fishoily, labels = c("0-4 yrs", "0-4 yrs", "5-9 yrs", "10+ yrs"))) %>% 
  select(sley, fishoily) %>% table()

# Menopause status
# Check data
lupus %>% select(sex, mtot, ageatmenopause)
lupus %>% filter(mtot == 0) %>% select(sex, mtot, ageatmenopause)
lupus %>% select(mtot) %>% table()

# Number of missing values on mtot: 580
lupus %>%
  filter(sex == "Female" & is.na(mtot)) %>% 
  tally()

# Compare proportions by SLE only among females
lupus %>% 
  filter(!is.na(mtot)) %>% 
  mutate(menopause = factor(mtot, labels = c("Pre-menopause", "Post-menopause"))) %>% 
  CreateTableOne("menopause", strata = "prev_sle", data =.) %>% 
  print(showAllLevels = TRUE)

# Models with menopause variable
lupus_menop <- lupus_md %>% 
  mutate(menopause = ifelse(sex == "Male", 0, mtot),
         menopause = factor(menopause, labels = c("Pre-menopause", "Post-menopause")),
         PM_female = (2 - as.numeric(sex)) * (as.numeric(menopause) - 1),
         sex = fct_relevel(sex, c("Male", "Female"))) %>% 
  filter(!is.na(PM_female))

# Sanity check
lupus_menop %>% select(sex, menopause) %>% table()
lupus_menop %>% select(sex, menopause, PM_female) %>% distinct()

RHS <- c("agecat", "black", "sex")
fm <- formula(paste("prev_sle ~", paste0(RHS, collapse = " + ")))
m1 <- glm(fm, data = lupus_menop, family = "binomial")
m2 <- update(m1, . ~ . + vegstat3)
m3 <- update(m1, . ~ . + vegstat3 + educat3)
m4 <- update(m1, . ~ . + vegstat3 + educat3 + smkever)
m5 <- update(m1, . ~ . + vegstat3 + educat3 + smkever + PM_female)

models <- list(m1, m2, m3, m4, m5)
ci <- list(exp(confint.default(m1)), 
           exp(confint.default(m2)), 
           exp(confint.default(m3)), 
           exp(confint.default(m4)), 
           exp(confint.default(m5)))
var_labels <- c("Age.: 30-39", 
                "Age.: 40-59", 
                "Race: Black", 
                "Sex.: Female", 
                "Diet: Vegetarians", 
                "Diet: Pesco veg", 
                "Educ: HS or less",
                "Educ: Some college",
                "Smkg: Ever", 
                "Mnps: Post-menopause")
stargazer::stargazer(models, 
                     type = "text", 
                     digits = 2,
                     dep.var.caption = "",
                     dep.var.labels = "Outcome: Prevalent SLE",
                     model.numbers = FALSE,
                     column.labels = c("Model 1", "Model 2", "Model 3", "Model 4", "Model 5"),
                     covariate.labels = var_labels,
                     apply.coef = exp, 
                     ci.custom = ci, 
                     star.cutoffs = NA, 
                     omit = "Constant", 
                     omit.stat = c("aic", "ll"),
                     omit.table.layout = "n")

# Comparing participants' characteristics for those with or without missing value on menopausal status
table_vars <- c("age", "agecat", "black", "sex", "smkever", "educat3", "vegstat3", "bmi", "bmicat")
lupus %>% 
  mutate(menopause = ifelse(sex == "Male", 0, mtot),
         menopause = factor(menopause, labels = c("Pre-menopause", "Post-menopause")),
         PM_female = (2 - as.numeric(sex)) * (as.numeric(menopause) - 1),
         menop_miss = ifelse(is.na(menopause), 1, 0),
         menop_miss = factor(menop_miss, labels = c("Not missing", "missing"))) %>% 
  CreateTableOne(table_vars, strata = "menop_miss", data = .) %>% 
  print(showAllLevels = TRUE)

# Interaction b/w dietary pattern and vd supp use
# m6 <- update(m1, . ~ . + vegstat3 * take_vd + smkever + educat3 + bmicat)
# summary(m6)
# anova(m5, m6, test = "LRT")[2, 5]
# 
# emmeans(m6, ~ take_vd | vegstat3, type = "response") %>% 
#   pairs(reverse = TRUE) %>% 
#   confint() %>% 
#   as_tibble() %>% 
#   select(-(4:5))
# 
# emmeans(m6, ~ vegstat3 | take_vd, type = "response") %>% 
#   pairs(reverse = TRUE) %>% 
#   confint()
# 
# calc_or <- function(model, L){
#   betas <- coef(model)
#   LB <- as.vector(L %*% betas)
#   OR <- exp(LB)
#   SE <- as.vector(sqrt(t(L) %*% vcov(model) %*% L))
#   CI <- exp(LB + qnorm(c(0.025, 0.975)) * SE)
#   c(OR = OR, lwr = CI[1], upr = CI[2])
# }
# 
# # OR associated with VD supp use in vegetarians
# L <- rep(0, m6$rank)
# L[c(8, 14)] <- 1
# vege <- calc_or(m6, L)
# 
# # OR associated with VD supp use in pesco
# L <- rep(0, m6$rank)
# L[c(8, 15)] <- 1
# pesco <- calc_or(m6, L)
# 
# # OR associated with VD supp use in non-vegetarians (ref)
# L <- rep(0, m6$rank)
# L[8] <- 1
# nonveg <- calc_or(m6, L)
# 
# # OR for vd supp use by dietary pattern
# round(rbind(vege, pesco, nonveg), 2)
# 
# # OR associated with vegetarians among those who use VD supp
# L <- rep(0, m6$rank)
# L[c(6, 14)] <- 1
# vege <- calc_or(m6, L)
# 
# # OR associated with pesco among those who use VD supp
# L <- rep(0, m6$rank)
# L[c(7, 15)] <- 1
# pesco <- calc_or(m6, L)
