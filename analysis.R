
# AHS-2 lupus study 2

# Required packages
pacs <- c("tidyverse", "tableone", "emmeans", "Gmisc")
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

filepath <- "./data/lupus-initial-dataset-v2-2022-06-03.csv"
lupus00  <- read_csv(filepath)
dim(lupus00)

lupus0 <- lupus0 %>% 
  inner_join(select(lupus00, analysisid, starts_with("p182"), starts_with("p204")))

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
    prev_sle = factor(prev_sle, labels = c("No", "Yes")),
    p182     = p182diet + p182supp,
    p204     = p204diet + p204supp) %>% 
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

# Omega-6: 
# LA     : p182diet, p182supp
# AA     : p204diet, p204supp

fa <- tribble(
  ~fa_name, ~lipid, ~note,
  "ALA", "p183", "Omega-3",
  "SDA", "p184", "Omega-3",
  "EPA", "p205", "Omega-3",
  "DPA", "p225", "Omega-3",
  "DHA", "p226", "Omega-3",
  "LA",  "p182", "Omega-6",
  "AA",  "p204", "Omega-6"
)

lupus %>% 
  select(all_of(fa$lipid)) %>% 
  summary()

# Percent of zero intake
lupus %>% 
  select(all_of(fa$lipid)) %>% 
  pivot_longer(p183:p204, names_to = "fa", values_to = "value") %>% 
  mutate(zeros = ifelse(value == 0, 1, 0)) %>% 
  group_by(fa) %>% 
  summarize(pct_zero = mean(zeros) * 100)

lupus %>% 
  select(all_of(fa$lipid)) %>% 
  pivot_longer(p183:p204, names_to = "fa", values_to = "value") %>% 
  # mutate(value = log(value + 1)) %>% 
  ggplot(aes(x = value)) +
  geom_histogram(bins = 20) +
  facet_grid(~ fa, scales = "free")

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
omega_vars         <- fa$lipid
omega_diet_vars    <- paste0(omega_vars, "diet")
omega_supp_vars    <- paste0(omega_vars, "supp")

omega_vars_ea      <- paste0(omega_vars, "_ea")
omega_diet_vars_ea <- paste0(omega_diet_vars, "_ea")

# Energy-adjust only dietary component (not supplement)
lupus[omega_diet_vars_ea] <- lapply(lupus[omega_diet_vars], kcal_adjust, kcal = lupus$kcal)

# Add energy-adjusted dietary intake and supplement
calc_total_ea <- function(var) rowSums(lupus[c(paste0(var, "diet_ea"), paste0(var, "supp"))])
lupus[omega_vars_ea] <- lapply(omega_vars, calc_total_ea)

# Sum omaga fa unadjusted values
lupus$n6pfa       <- rowSums(lupus[c("p182", "p204")])
lupus$p205p226    <- rowSums(lupus[c("p205", "p226")])

# Sum omaga fa energy-adjusted values
lupus$n3pfa_ea    <- rowSums(lupus[c("p183_ea", "p184_ea", "p205_ea", "p225_ea", "p226_ea")])
lupus$n6pfa_ea    <- rowSums(lupus[c("p182_ea", "p204_ea")])
lupus$p205p226_ea <- rowSums(lupus[c("p205_ea", "p226_ea")])

# Sum omaga fa energy-adjusted dietary values
lupus$n3pfa_diet_ea    <- rowSums(lupus[c("p183diet_ea", "p184diet_ea", "p205diet_ea", "p225diet_ea", "p226diet_ea")])
lupus$n6pfa_diet_ea    <- rowSums(lupus[c("p182diet_ea", "p204diet_ea")])
lupus$p205p226_diet_ea <- rowSums(lupus[c("p205diet_ea", "p226diet_ea")])

# Ratio of dietary to total intake (after energy-adjustment)
lupus %>% 
  mutate(p183_diet_ratio     = p183diet_ea / p183_ea,
         n3pfa_diet_ratio    = n3pfa_diet_ea / n3pfa_ea,
         n6pfa_diet_ratio    = n6pfa_diet_ea / n6pfa_ea,
         p205p226_diet_ratio = p205p226_diet_ea / p205p226_ea) %>% 
  pivot_longer(ends_with("_ratio"), names_to = "var", values_to = "value") %>% 
  mutate(var = factor(var, levels = c("p183_diet_ratio", "p205p226_diet_ratio", "n3pfa_diet_ratio", "n6pfa_diet_ratio"))) %>% 
  group_by(var) %>% 
  summarize(mean = round(mean(value, na.rm = TRUE), 4))

# Calculate ratio of FA
# Get quartiles of ratio variables
lupus <- lupus %>% 
  mutate(o3_o6       = n3pfa_ea / n6pfa_ea,
         p183_o6     = p183_ea / n6pfa_ea,
         p205p226_o6 = p205p226_ea / n6pfa_ea,
         o3_o6_cat       = ntile(o3_o6, 4),
         o3_o6_cat       = factor(o3_o6_cat),
         p183_o6_cat     = ntile(p183_o6, 4),
         p183_o6_cat     = factor(p183_o6_cat),
         p205p226_o6_cat = ntile(p205p226_o6, 4),
         p205p226_o6_cat = factor(p205p226_o6_cat))

# Descriptive table
# Demographics and lifestyles
table_vars <- c("age", "agecat", "black", "sex", "smkever", "educat3", "vegstat3", "take_fo", "bmi", "bmicat", "kcal")
lupus %>% CreateTableOne(table_vars, strata = "prev_sle", data = .) %>%
  print(showAllLevels = TRUE, pDigits = 4)

# FA quartiles by SLE status
table_vars <- c("o3_o6_cat", "p205p226_o6_cat", "p183_o6_cat")
lupus %>% CreateTableOne(table_vars, strata = "prev_sle", data = .) %>%
  print(showAllLevels = TRUE, pDigits = 4)

# Cut-off values
lupus %>% 
  select(starts_with("o3_o6")) %>% 
  group_by(o3_o6_cat) %>% 
  summarize(min = min(o3_o6), max = max(o3_o6))

lupus %>% 
  select(starts_with("p205p226_o6")) %>% 
  group_by(p205p226_o6_cat) %>% 
  summarize(min = min(p205p226_o6), max = max(p205p226_o6))

lupus %>% 
  select(starts_with("p183_o6")) %>% 
  group_by(p183_o6_cat) %>% 
  summarize(min = min(p183_o6), max = max(p183_o6))

# Omega-3 and -6 fatty acids
#table_vars <- c("p183", "p205p226", "n3pfa", "n6pfa")
table_vars <- c("p183_ea", "p205p226_ea", "n3pfa_ea", "n6pfa_ea")

# Check distribution
lupus %>% 
  select(all_of(table_vars)) %>% 
  pivot_longer(p183_ea:n6pfa_ea, names_to = "var", values_to = "value") %>% 
  mutate(var = factor(var, levels = table_vars))  %>% 
  ggplot(aes(x = value)) +
  geom_histogram(bins = 50) +
  facet_grid(~var, scales = "free") +
  labs(x = "Energy-adjusted intake (gram/day")

# Check Spearman correlations
lupus %>% 
  select(all_of(table_vars)) %>% 
  cor(method = "spearman") %>% 
  round(3)

# Table by SLE status
lupus %>% CreateTableOne(table_vars, strata = "prev_sle", data = .) %>%
  print(showAllLevels = TRUE, pDigits = 4, nonnormal = table_vars)

lupus %>% 
  set_column_labels(prev_sle    = "Prevalent SLE", 
                    p183_ea     = "ALA",
                    p205p226_ea = "DHA + EPA",
                    n3pfa_ea    = "Omega-3",
                    n6pfa_ea    = "Omega-6") %>% 
  getDescriptionStatsBy(all_of(table_vars), 
                        by = prev_sle, 
                        continuous_fn = describeMedian,
                        digits = 2,
                        statistics = TRUE) %>% 
  htmlTable(caption = "Median (IQR) energy-adjusted intake of fatty acids (gram/day)",
            tfoot = "P-values were from Mann-Whitney tests")

# Ratios
table_vars <- c("o3_o6", "p205p226_o6", "p183_o6")

# Check distribution
lupus %>% 
  select(all_of(table_vars)) %>% 
  pivot_longer(o3_o6:p183_o6, names_to = "var", values_to = "value") %>% 
  mutate(var = factor(var, levels = table_vars))  %>% 
  ggplot(aes(x = value)) +
  geom_histogram(bins = 50) +
  facet_grid(~var, scales = "free") +
  labs(x = "Ratio of energy-adjusted FA intake (gram/day")

# Check Spearman correlations
lupus %>% 
  select(all_of(table_vars)) %>% 
  cor(method = "spearman") %>% 
  round(3)

# Check VIFs
temp <- lm(as.numeric(prev_sle) ~ o3_o6_cat + p205p226_o6_cat + p183_o6_cat, data = lupus)
car::vif(temp)
  
# Table by SLE status
lupus %>% CreateTableOne(table_vars, strata = "prev_sle", data = .) %>%
  print(showAllLevels = TRUE, contDigits = 4, pDigits = 4, nonnormal = table_vars)

lupus %>% 
  set_column_labels(prev_sle    = "Prevalent SLE", 
                    o3_o6       = "Omega-3/Omega-6",
                    p205p226_o6 = "(DHA + EPA)/Omega-6",
                    p183_o6     = "ALA/Omega-6") %>% 
  getDescriptionStatsBy(all_of(table_vars), 
                        by = prev_sle, 
                        continuous_fn = describeMedian,
                        digits = 4,
                        statistics = TRUE) %>% 
  htmlTable(caption = "Median (IQR) ratio of fatty acids",
            tfoot = "P-values were from Mann-Whitney tests")

# Logistic regression
# Change references
lupus_md <- lupus %>% 
  mutate(kcal100 = kcal / 100)
lupus_md$vegstat3 <- relevel(lupus_md$vegstat3, ref = "Non-veg")
lupus_md$educat3 <- relevel(lupus_md$educat3, ref = "Col grad")
lupus_md$agecat <- relevel(lupus_md$agecat, ref = ">=60")

fm <- formula(prev_sle ~ o3_o6_cat + p205p226_o6_cat + p183_o6_cat)
m1 <- glm(fm, family = binomial, data = lupus_md)
m2 <- update(m1, .~. + take_fo + agecat + black + sex + educat3 + smkever)
m3 <- update(m2, .~. + vegstat3)
m4 <- update(m3, .~. +  bmicat)

models <- list(m1, m2, m3, m4)
ci <- list(exp(confint.default(m1)), 
           exp(confint.default(m2)), 
           exp(confint.default(m3)), 
           exp(confint.default(m4)))
var_labels <- c("O3/O6: Q2",
                "O3/O6: Q3",
                "O3/O6: Q4",
                "DHA+EPA/O6: Q2",
                "DHA+EPA/O6: Q3",
                "DHA+EPA/O6: Q4",
                "ALA/O6: Q2",
                "ALA/O6: Q3",
                "ALA/O6: Q4",
                "FOil: Yes",
                "Age.: 30-39", 
                "Age.: 40-59", 
                "Race: Black", 
                "Sex.: Male", 
                "Educ: HS or less",
                "Educ: Some college",
                "Smkg: Ever", 
                "Diet: Vegetarians", 
                "Diet: Pesco veg", 
                "BMI.: Overweight",
                "BMI.: Obese")
stargazer::stargazer(models, 
                     type = "text", 
                     digits = 2,
                     dep.var.caption = "",
                     dep.var.labels = "Outcome: Prevalent SLE",
                     model.numbers = FALSE,
                     column.labels = c("Model 1", "Model 2", "Model 3", "Model 4"),
                     covariate.labels = var_labels,
                     apply.coef = exp, 
                     ci.custom = ci, 
                     star.cutoffs = NA, 
                     omit = "Constant", 
                     omit.stat = c("aic", "ll"),
                     omit.table.layout = "n")
