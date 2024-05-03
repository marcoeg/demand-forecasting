#
# -- Time Series Forecasting using Prophet
#

# ----------  Exploratory Data Analysis
#
# The dataset contains 5-years of store-item unit sales data for 50 items 
# across 10 different stores (913,000 observations).
#

# Load raw dataset
#
# Note: change the working directory to the same of the this source file location
library(readr)
sales_train <- read_csv("./dataset/train.csv")

library(dplyr)
library(knitr)
library(ggplot2)
library(gridExtra)
library(prophet)

# 1. Count the distinct stores
num_stores <- sales_train %>%
  distinct(store) %>%
  nrow()

# Count the distinct items
num_items <- sales_train %>%
  distinct(item) %>%
  nrow()

# Print the results
cat("Number of stores:", num_stores, "\n")
cat("Number of items:", num_items, "\n")

# 2. Find the start and end dates
#
# Convert the date column to Date type if needed
sales_train$date <- as.Date(sales_train$date)

# Find the minimum and maximum dates
min_date <- min(sales_train$date)
max_date <- max(sales_train$date)

# Format the dates as strings
min_date_str <- format(min_date, "%Y-%m-%d")
max_date_str <- format(max_date, "%Y-%m-%d")

# Print the time range
cat("Time Range:\n")
cat("Start Date:", min_date_str, "\n")
cat("End Date:", max_date_str, "\n")

# 3. Group the data by store and count the number of unique items in each store
items_per_store <- sales_train %>%
  group_by(store) %>%
  summarize(num_items = n_distinct(item))

# Print the result
print(items_per_store)

# 4. Compute summary statistics for each store
store_summary <- sales_train %>%
  group_by(store) %>%
  summarise(
    count = n(),                # Count of sales
    sum = sum(sales),           # Sum of sales
    mean = mean(sales),         # Mean of sales
    median = median(sales),     # Median of sales
    std = sd(sales),            # Standard deviation of sales
    min = min(sales),           # Minimum sales
    max = max(sales)            # Maximum sales
  )

# Print the summary statistics as a nice table
kable(store_summary, 
      caption = "Summary Statistics for Each Store",
      align = "c")

# 5. Summary statistics for each item
item_summary <- sales_train %>%
  group_by(item) %>%
  summarise(
    count = n(),                # Count of sales
    sum = sum(sales),           # Sum of sales
    mean = mean(sales),         # Mean of sales
    median = median(sales),     # Median of sales
    std = sd(sales),            # Standard deviation of sales
    min = min(sales),           # Minimum sales
    max = max(sales)            # Maximum sales
  )

# Print the summary statistics using kable
kable(item_summary, caption = "Summary Statistics for Each Item")

# 6. Histograms of store sales

# Create a list to store individual plots
plots <- list()

# Loop through each store
for (i in 1:10) {
  # Subset data for the current store
  subset_data <- subset(sales_train, store == i)
  
  # Create histogram plot for sales
  hist_plot <- ggplot(subset_data, aes(x = sales)) +
    geom_histogram(fill = "skyblue", color = "black", bins = 30) +
    labs(title = paste("Store", i), x = "Sales", y = "Frequency") +
    theme_minimal()
  
  # Add the plot to the list
  plots[[i]] <- hist_plot
}

# Arrange plots in a grid
grid.arrange(grobs = plots, ncol = 2)  

# 7. Sales distribution of the first 10 items in the 1st store

# Subset data for store 1
sub <- subset(sales_train, store == 1)

# Create a list to store individual plots
plots <- list()

# Loop through each item
for (i in 1:10) {
  # Subset data for the current item
  subset_data <- subset(sub, item == i)
  
  # Create line plot for sales
  line_plot <- ggplot(subset_data, aes(x = date, y = sales, color = factor(item))) +
    geom_line() +
    labs(title = paste("Item", i, "Sales"), x = "Date", y = "Sales") +
    theme_minimal()
  
  # Add the plot to the list
  plots[[i]] <- line_plot
}

# Arrange plots in a grid
grid.arrange(grobs = plots, nrow = 5, ncol = 2, top = "Histogram: Sales", 
             left = "Frequency", right = "Sales")

# 8. Correlation between total sales of stores

# First, aggregate sales by date and store
storesales <- aggregate(sales ~ date + store, data = sales_train, sum)

# Then, reshape the data to have stores as columns and dates as rows
# You can use the 'reshape' function in base R for this
reshaped <- reshape(storesales, idvar = "date", timevar = "store", direction = "wide")

# Calculate the correlation matrix
corr <- cor(reshaped[, -1], method = "spearman")
kable(corr, caption="Correlation matrix")

# Plot the heatmap
ggplot(data = as.data.frame.table(corr), aes(x = Var1, y = Var2, fill = Freq)) +
  geom_tile() +
  scale_fill_gradient(low = "red", high = "green") +
  labs(title = "Correlation Heatmap", x = "Store", y = "Store")

#
# ----------  Build a Single Forecast 

# 1. assemble the historical dataset on which we will train the model
#
train_data_filtered <- sales_train %>%
     filter(store == 1 & item == 1) %>%
     mutate(ds = as.Date(date), y = sales) %>%
     select(ds, y) %>%
     arrange(ds)

head(train_data_filtered)
# count the number of rows in train_data_filtered
nrow(train_data_filtered)

# 2. instantiate and train a prophet model
#

m <- prophet(
  growth = "linear",  # Specify growth type (linear or logistic)
  seasonality.mode = "additive",  # Specify seasonality mode (additive or multiplicative)
  changepoint.prior.scale = 0.05,  # Specify changepoint prior scale
  seasonality.prior.scale = 10,  # Specify seasonality prior scale
  yearly.seasonality = TRUE,  # Include yearly seasonality
  weekly.seasonality = TRUE,  # Include weekly seasonality
  daily.seasonality = FALSE  # Do not Include daily seasonality
)

m <- fit.prophet(m, train_data_filtered)

# 3. build a90-days forecast beyond the last available date
future_days <- make_future_dataframe(m, periods = 90)
forecast <- predict(m, future_days)

head(forecast[c('ds', 'yhat', 'yhat_lower', 'yhat_upper')])

# 4. examine forecast components
prophet_plot_components(m, forecast)

# 5. view historical vs. predictions
m_saved <- m # save model from plot adjustment

# adjust model history for plotting purposes
m$history <- dplyr::filter(m$history, lubridate::with_tz(m$history$ds, tzone = "UTC") > ymd("2017-01-01"))

# plot history and forecast for relevant period
plot(
  m,
  filter(forecast, forecast$ds > ymd("2017-01-01")),
  xlabel='date',
  ylabel='sales'
)
m <- m_saved

# 6. Evaluate the forecast
#
# Calculate Mean Absolute Error, Mean Squared Error and Root Mean Squared Error

#---------------
# Define parameters for cross-validation
initial_training_period <- 730  # Initial training period in days
forecast_horizon <- 45          # Forecast horizon for cross-validation in days
evaluation_period <- 90         # Evaluation period for cross-validation in days

# Call cross_validation with adjusted parameters
df.cv <- cross_validation(
  m, 
  initial = initial_training_period, 
  period = evaluation_period, 
  horizon = forecast_horizon, 
  units = 'days'
)

df.p <- performance_metrics(df.cv)
head(df.p)

# Reshape the data frame to long format
df.p.long <- pivot_longer(df.p, cols = c(mse, rmse, mae, mape, mdape, smape),
                          names_to = "metric", values_to = "value")

# plot the metrics over the horizon using faceting
ggplot(df.p.long, aes(x = horizon, y = value)) +
  geom_line() +
  geom_point() +
  facet_wrap(~ metric, scales = "free_y") +
  labs(title = "Performance Metrics over Different Horizons",
       x = "Horizon (days)", y = "Metric Value") +
  theme_minimal() +
  theme(panel.spacing = unit(1, "lines"))  # Adjust spacing between facets

# End forecasting
#
# --------------------------------

