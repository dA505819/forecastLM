#' Training a Forecasting Model with Linear Regression Framework
#' @export
#' @param input A tsibble or ts object
#' @param y A character, the column name of the depended variable of the input object, required (and applicable) only when the input is tsibble object
#' @param x A character, the column names of the independent variable of the input object, applicable when using tsibble object with regressors
#' @param seasonal A character, optional, create categorical variable/s to model the single or multiple seasonal components. Supporting the
#' following frequencies structure:
#'
#' `quarter` - for quarterly frequency
#'
#' `month` - for monthly frequency
#'
#' `week` - for weekly frequency
#'
#' `yday` - for daily frequency
#'
#' `wday` - for day of the week frequency
#'
#' `hour` - for hourly frequency
#'
#' The argument supports multiple seasonality cases such as daily and day of the week effect
#'
#' @param trend A list, define the trend structure. Possible arguments -
#'
#' `linear`, a boolean variable, if set to TRUE defines a linear trend (e.g., index of 1,2,3,...,t, for a series with t observations)
#'
#' `power``, a numeric value, defines the polynomial degree of the series index (for example, a power = 0.5 define a square root index and power = 2 represents a squared index).
#' By default set to NULL
#'
#' `exponential`, a boolean variable, if set to TRUE defines an exponential trend
#'
#' `log`, a boolean variable, if set to TRUE defines a log transformation for the trend.
#'
#' By default, the `trend` argument is set to a linear trend (i.e., power = 1)
#'
#' @param lags A positive integer, defines the series lags to be used as input to the model (equivalent to AR process)
#' @param events A list, optional, create hot encoding variables based on date/time objects,
#' where the date/time objects must align with the input object index class (may not work when the input object is 'ts')
#' @param knots A list, optional, create a piecewise linear trend variables based on date/time objects as a starting point of each knot,
#' where the date/time objects must align with the input object index class (may not work when the input object is 'ts')
#' @param scale A character, scaling options of the series, methods available -
#' c("log", "normal", "standard") for log transformation, normalization, or standardization of the series, respectively.
#' If set to NULL (default), no transformation will occur
#' @param step A boolean, if set to TRUE will use apply the stepwise function for variable selection using the \code{\link[stats]{step}} function
#' @param ... Optional, a list of arguments to pass to the \code{\link[stats]{step}} function
#' @description Methods for forecasting regular time series data based on a linear regression model
#' @details The trainLM function provides a flexible framework for forecasting regular time-series data with the linear regression model with the \code{\link[stats]{lm}} function.
#' The function arguments enable a fast extraction and generation of new features from the input series, such as seasonal, trend, lags, outliers, and special events.
#' @examples
#' data(ny_gas)
#'
#' head(ny_gas)
#'
#' # Fitting basic model with linear trend
#' md1 <- trainLM(input = ny_gas,
#'                y = "y",
#'                trend = list(linear = TRUE))
#'
#'
#' # Getting the regression summary
#'
#' summary(md1$model)
#'
#' # Plotting the residauls of the model
#' plot_res(md1)
#'
#' # Adding monthly seasonal component
#' md2 <- trainLM(input = ny_gas,
#'                y = "y",
#'                trend = list(linear = TRUE),
#'                seasonal = "month")
#'
#'
#' plot_res(md2)
#'
#' # Adding the first and seasonal lags
#'
#' md3 <- trainLM(input = ny_gas,
#'                y = "y",
#'                trend = list(linear = TRUE),
#'                seasonal = "month",
#'                lags = c(1, 12))
#'
#' plot_res(md3)
#'
#' # Adding more lags and using stepwise regression for variable selection
#' md4 <- trainLM(input = ny_gas,
#'                y = "y",
#'                trend = list(linear = TRUE),
#'                seasonal = "month",
#'                lags = c(1:12),
#'                step = TRUE)
#'
#' summary(md4$model)
#'
#' plot_res(md4)



trainLM <- function(input,
                    y = NULL,
                    x = NULL,
                    seasonal = NULL,
                    trend = list(linear = TRUE, exponential = FALSE, log = FALSE, power = FALSE),
                    lags = NULL,
                    knots = NULL,
                    events = NULL,
                    scale = NULL,
                    step = FALSE,
                    ...){
  #----------------Set variable and functions----------------

  `%>%` <- magrittr::`%>%`

  freq <- md <- time_stamp <- new_features <- residuals <- scaling_parameters <- fitted  <- NULL
  #----------------Error handling----------------
  # Checking the trend argument

  if(!base::is.list(trend) || !all(base::names(trend) %in% c("linear", "exponential", "log", "power"))){
    stop("The 'trend' argument is not valid")
  } else{

    if(!"linear" %in% base::names(trend)){
      trend$linear <- FALSE
    } else if(!base::is.logical(trend$linear)){
      stop("The 'linear' argument of the trend must be either TRUE or FALSE")
    }

    if(!"exponential" %in% base::names(trend)){
      trend$exponential <- FALSE
    } else if(!base::is.logical(trend$exponential)){
      stop("The 'exponential' argument of the trend must be either TRUE or FALSE")
    }

    if(!"log" %in% base::names(trend)){
      trend$log <- FALSE
    } else if(!base::is.logical(trend$log)){
      stop("The 'log' argument of the trend must be either TRUE or FALSE")
    }

    if(!"power" %in%  base::names(trend)){
      trend$power <- FALSE
    } else if(!base::is.null(trend$power) && !base::is.numeric(trend$power) && trend$power != FALSE){
      stop("The value of the 'power' argument is not valid, can be either a numeric ",
           "(e.g., 2 for square, 0.5 for square root, etc.), or FALSE for disable")
    }

    if(trend$linear && !base::is.null(trend$power) && trend$power == 1){
      warning("Setting both the 'power' argument to 1 and the 'linear' argument to TRUE is equivalent. ",
              "To avoid redundancy in the variables, setting 'linear' to FALSE")
    }
  }

  # Check if the x variables are in the input obj
  if(!base::is.null(x)){
    if(!base::all(x %in% names(input))){
      stop("Some or all of the variables names in the 'x' argument do not align with the column names of the input object")
    }
  }


  # Checking the lags argument
  if(!base::is.null(lags)){
    if(!base::is.numeric(lags) || base::any(lags %% 1 != 0 ) || base::any(lags <= 0)){
      stop("The value of the 'ar' argument is not valid. Must be a positive integer")
    }
  }

  # Checking the scale argument
  if(!is.null(scale)){
    if(base::length(scale) > 1 || !base::any(c("log", "normal", "standard") %in% scale)){
      stop("The value of the 'scale' argument are not valid")
    }
  }
  #----------------Setting the input table----------------
  # Check the input class
  if(base::any(base::class(input) == "tbl_ts")){
    df <- input
    # Check the y argument
    if(is.null(y) || !y %in% base::names(df)){
      stop("The 'y' argument is missing or not exists on the 'input' object")
    }
  } else if(any(class(input) == "ts")){
    y <- base::deparse(base::substitute(input))
    df <- tsibble::as_tsibble(input) %>% stats::setNames(c("index", y))
    if(!base::is.null(x)){
      warning("The 'x' argument cannot be used when input is a 'ts' class")
    }
    x <- NULL
  }

  time_stamp <- base::attributes(df)$index2

  freq <- base::list(unit = base::names(base::which(purrr::map(tsibble::interval(df), ~.x) > 0)),
                     value = tsibble::interval(df)[which(tsibble::interval(df) != 0)] %>% base::as.numeric(),
                     frequency = stats::frequency(df),
                     class = base::class(df[,time_stamp, drop = TRUE]))

  #----------------Checking the event argument----------------
  if(!base::is.null(events) && !base::is.list(events)){
    stop("The 'events' argument is not valid, please use list")
  } else if(!base::is.null(events) && base::is.list(events)){
    for(n in base::names(events)){
      if(!base::any(freq$class %in% base::class(events[[n]]))){
        stop("The date/time object of the 'events' argument does not align with the ones of the input object")
      } else {
        df[n] <- 0
        df[base::which(df[,time_stamp , drop = TRUE] %in% events[[n]]), n] <- 1
        new_features <- c(new_features, n)
      }
    }
  }

  #----------------Checking the knots argument----------------
  if(!base::is.null(knots) && !base::is.list(knots)){
    stop("The 'knots' argument is not valid, please use list")
  } else if(!base::is.null(knots) && base::is.list(knots)){
    for(n in base::names(knots)){
      if(!base::any(freq$class %in% base::class(knots[[n]]))){
        stop("The date/time object of the 'knots' argument does not align with the ones of the input object")
      } else {
        first <- NULL
        first <- which(df[, time_stamp, drop = TRUE] > knots[[n]])[1]
        df[n] <- base::pmax(0, 1:nrow(df) - first - 1)
        new_features <- c(new_features, n)
      }
    }
  }
  #----------------Scalling the series----------------
  if(!base::is.null(scale)){
    y_temp <- NULL
    if(scale == "log"){
      df[[base::paste(y,"log", sep = "_")]] <- base::log(df[[y]])
      y_temp <- y
      y <- base::paste(y,"log", sep = "_")
      scaling_parameters <- NULL
    } else if(scale == "normal"){
      # Set the transformation weights
      normal_min <- base::min(df[[y]])
      normal_max <- base::max(df[[y]])
      scaling_parameters <- list(normal_min = normal_min, normal_max = normal_max)

      df[[base::paste(y,"normal", sep = "_")]] <- (df[[y]] - normal_min) /
        (normal_max - normal_min)
      y_temp <- y
      y <- base::paste(y,"normal", sep = "_")
    } else if(scale == "standard"){
      # Set the transformation weights
      standard_mean <-  base::mean(df[[y]])
      standard_sd <- stats::sd(df[[y]])
      scaling_parameters <- list(standard_mean = standard_mean, standard_sd = standard_sd)

      df[[base::paste(y,"standard", sep = "_")]] <- (df[[y]] - standard_mean) /
        standard_sd
      y_temp <- y
      y <- base::paste(y,"standard", sep = "_")
    }
  }
  #----------------Setting the frequency component----------------
  if(!base::is.null(seasonal)){

    # Case series frequency is quarterly
    if(freq$unit == "quarter"){
      if(base::length(seasonal) == 1 & seasonal == "quarter"){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "quarter")
      } else if(base::length(seasonal) > 1 & "quarter" %in% seasonal){
        warning("Only quarter seasonal component can be used with quarterly frequency")
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "quarter")
      } else {
        stop("The seasonal component is not valid")
      }

      # Case series frequency is monthly

    } else if(freq$unit == "month"){
      if(base::length(seasonal) == 1 && seasonal == "month"){
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "month")
      } else if(all(seasonal %in% c("month", "quarter"))){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "month", "quarter")
      } else if(any(seasonal %in% c("month", "quarter"))){
        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }

        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }

      } else {stop("The seasonal component is not valid")}

      # Case series frequency is weekly

    } else if(freq$unit == "week"){
      if(base::length(seasonal) == 1 && seasonal == "week"){
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "week")
      } else if(all(c("week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "week","month", "quarter")
      } else if(any(c("week", "month", "quarter") %in% seasonal)){
        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }

        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }

        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }
      } else {stop("The seasonal component is not valid")}

      # Case series frequency is daily

    } else if(freq$unit == "day"){
      if(base::length(seasonal) == 1 && seasonal == "wday"){
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "wday")
      } else if(base::length(seasonal) == 1 && seasonal == "yday"){
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "yday")
      } else if(all(c("wday", "yday","week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "wday", "yday", "week","month", "quarter")
      } else if(any(c("wday", "yday","week", "month", "quarter") %in% seasonal)){
        if("wday" %in% seasonal){
          df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "wday")
        }

        if("yday" %in% seasonal){
          df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "yday")
        }

        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }


        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }

        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }

      } else {stop("The seasonal component is not valid")}

      # Case series frequency is hourly

    } else if(freq$unit == "hour"){
      if(base::length(seasonal) == 1 && seasonal == "hour"){
        df$hour <- lubridate::hour(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "hour")
      } else if(all(c("hour", "wday", "yday","week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
        new_features <- c(new_features, "hour","wday", "yday", "week","month", "quarter")
      } else if(any(c("hour","wday", "yday","week", "month", "quarter") %in% seasonal)){
        if("hour" %in% seasonal){
          df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "hour")
        }

        if("wday" %in% seasonal){
          df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "wday")
        }

        if("yday" %in% seasonal){
          df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "yday")
        }

        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }

        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }

        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }

      } else {stop("The seasonal component is not valid")}
    } else if(freq$unit == "minute"){
      if(base::length(seasonal) == 1 && seasonal == "minute"){
        df$minute <- (lubridate::hour(df[[time_stamp]]) * 2 + (lubridate::minute(df[[time_stamp]]) + freq$value )/ freq$value )%>%
          factor(ordered = FALSE)
        new_features <- c(new_features, "minute")
      } else if(all(c("minute", "hour", "wday", "yday","week", "month", "quarter") %in% seasonal)){
        df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
        df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
        df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
        df$minute <- (lubridate::hour(df[[time_stamp]]) * 2 + (lubridate::minute(df[[time_stamp]]) + freq$value )/ freq$value) %>%
          base::factor(ordered = FALSE)
        new_features <- c(new_features, "minute", "hour","wday", "yday", "week","month", "quarter")
      } else if(any(c("minute", "hour","wday", "yday","week", "month", "quarter") %in% seasonal)){
        if("minute" %in% seasonal){
          df$minute <- (lubridate::hour(df[[time_stamp]]) * 2 + (lubridate::minute(df[[time_stamp]]) + freq$value )/ freq$value) %>%
            base::factor(ordered = FALSE)
          new_features <- c(new_features, "minute")
        }

        if("hour" %in% seasonal){
          df$hour <- (lubridate::hour(df[[time_stamp]]) + 1) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "hour")
        }

        if("wday" %in% seasonal){
          df$wday <- lubridate::wday(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "wday")
        }

        if("yday" %in% seasonal){
          df$yday <- lubridate::yday(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "yday")
        }

        if("week" %in% seasonal){
          df$week <- lubridate::week(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "week")
        }

        if("month" %in% seasonal){
          df$month <- lubridate::month(df[[time_stamp]], label = TRUE) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "month")
        }

        if("quarter" %in% seasonal){
          df$quarter <- lubridate::quarter(df[[time_stamp]]) %>% base::factor(ordered = FALSE)
          new_features <- c(new_features, "quarter")
        }

      } else {stop("The seasonal component is not valid")}
    }
  }

  #----------------Setting the trend----------------
  if(base::is.numeric(trend$power)){
    for(i in trend$power){
      df[[base::paste("trend_power_", i, sep = "")]] <- c(1:base::nrow(df)) ^ i
      new_features <- c(new_features, base::paste("trend_power_", i, sep = ""))
    }
  }

  if(trend$exponential){
    df$exp_trend <- base::exp(1:base::nrow(df))
    new_features <- c(new_features, "exp_trend")
  }

  if(trend$log){
    df$log_trend <- base::log(1:base::nrow(df))
    new_features <- c(new_features, "log_trend")
  }

  if(trend$linear){
    df$linear_trend <- 1:base::nrow(df)
    new_features <- c(new_features, "linear_trend")
  }

  #----------------Setting the lags variables----------------

  if(!base::is.null(lags) && base::is.null(scale)){
    for(i in lags){
      df[base::paste("lag_", i, sep = "")] <- df[[y]] %>% dplyr::lag( i)
      new_features <- c(new_features, base::paste("lag_", i, sep = ""))
    }
    df1 <- df[(max(lags)+ 1):base::nrow(df),]
  } else if(!base::is.null(lags) && !base::is.null(scale)){
    for(i in lags){
      df[base::paste("lag_scale", i, sep = "")] <- df[[y]] %>% dplyr::lag(i)
      new_features <- c(new_features, base::paste("lag_scale", i, sep = ""))
    }
    df1 <- df[(max(lags)+ 1):base::nrow(df),]
  } else {
    df1 <- df
  }


  if(!base::is.null(x)){
    f <- stats::as.formula(paste(y, "~ ", paste0(x, collapse = " + "), "+", paste0(new_features, collapse = " + ")))
  } else{
    f <- stats::as.formula(paste(y, "~ ", paste0(new_features, collapse = " + ")))
  }

  if(!base::is.null(scale)){
    y <- y_temp
  }


  if(step){
    md_init <- NULL
    md_init <- stats::lm(f, data = df1)
    md <- stats::step(object = md_init, ...)
  } else(
    md <- stats::lm(f, data = df1)
  )

  #----------------Rescale the output ----------------
  if(base::is.null(scale)){
    fitted <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                               fitted = stats::predict(md, newdata = df1))

    residuals <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                                  residuals =  df1[[y]] -  fitted$fitted) %>%
      tsibble::as_tsibble(index = "index")
  } else if(!base::is.null(scale) && scale == "log"){
    fitted <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                               fitted = base::exp(stats::predict(md, newdata = df1)))

    residuals <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                                  residuals =  df1[[y]] -  fitted$fitted) %>%
      tsibble::as_tsibble(index = "index")
  } else if(!base::is.null(scale) && scale == "normal"){
    fitted <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                               fitted = (stats::predict(md, newdata = df1)) * (normal_max - normal_min)  +  normal_min)



    residuals <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                                  residuals =  df1[[y]] -  fitted$fitted) %>%
      tsibble::as_tsibble(index = "index")
  } else if(!base::is.null(scale) && scale == "standard"){
    fitted <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                               fitted = ((stats::predict(md, newdata = df1)) * standard_sd  +  standard_mean))



    residuals <- base::data.frame(index = df1[[base::attributes(df1)$index2]],
                                  residuals =  df1[[y]] -  fitted$fitted) %>%
      tsibble::as_tsibble(index = "index")
  }



  #----------------Setting the output----------------

  output <- list(model = md,
                 fitted = fitted,
                 residuals = residuals,
                 parameters = list(y = y,
                                   x = x,
                                   index = time_stamp,
                                   new_features = new_features,
                                   seasonal = seasonal,
                                   trend = trend,
                                   lags = lags,
                                   events = events,
                                   knots = knots,
                                   step = step,
                                   scale = scale,
                                   scaling_parameters = scaling_parameters,
                                   frequency = freq),
                 series = df)

  final_output <- base::structure(output, class = "trainLM")

  return(final_output)

}

#' Forecast trainML Model
#' @export
#' @param model A trainLM object
#' @param newdata A tsibble object, must be used when the input model was trained with external inputs (i.e., the 'x' argument of the trainML function was used). This input must follow the following structure:
#'
#' - Use the same time intervals (monthly, daily, hourly, etc.) structure and timestamp class (e.g., yearquarter, yearmonth, POSIXct, etc.) as the original input
#'
#' - The number of observations must align with the forecasting horizon (the 'h' argument)
#'
#' -  The timestamp of the first observation must be the consecutive observation of the last observation of the original series
#' @param h An integer, define the forecast horizon
#' @param pi A vector with numeric values between 0 and 1, define the level of the confidence of the prediction intervals of the forecast. By default calculate the 80\% and 95\% prediction intervals
#' @description Forecast trainML models
#' @examples
#' data(ny_gas)
#'
#' head(ny_gas)
#'
#' # Training a model
#' md <- trainLM(input = ny_gas,
#'               y = "y",
#'               trend = list(linear = TRUE),
#'               seasonal = "month",
#'               lags = c(1, 12))
#'
#' # Forecasting the future observations
#' fc <- forecastLM(model = md,
#'                  h = 60)
#'
#' # Plotting the forecast
#' plot_fc(fc)


forecastLM <- function(model, newdata = NULL, h, pi = c(0.95, 0.80)){
  #----------------Set variables and functions----------------
  `%>%` <- magrittr::`%>%`

  forecast_df <- df_names <- freq <- NULL
  #---------------- Error handling ----------------

  if(class(model) != "trainLM"){
    stop("The input model is invalid, must be a 'trainLM' object")
  }

  if(!base::is.numeric(pi) || base::any(pi <=0) || base::any(pi >= 1)){
    stop("The value of the 'pi' argument is not valid")
  }

  if(base::is.null(h)){
    stop("The forecast horizon argument, 'h', is missing")
  } else if(!base::is.numeric(h)){
    stop("The forecast horizon argument, 'h', must be integer")
  } else if(h %% 1 != 0){
    stop("The forecast horizon argument, 'h', must be integer")
  }

  if(!base::is.null(model$parameters$x) && base::is.null(newdata)){
    stop("The input model was trained with regressors, the 'newdata' argument must align to the 'x' argument of the trained model")
  } else if(!base::is.null(model$parameters$x) && !base::all(model$parameters$x %in% base::names(newdata))){
    stop("The columns names of the 'newdata' input is not aligned with the variables names that was used on the training process")
  } else if(!base::is.null(model$parameters$x) && !base::is.null(newdata) && base::nrow(newdata) != h){
    warning("The length of the input data ('newdata') is not aligned with the forecast horizon ('h'). Setting the forecast horizon as the number of rows of the input data.")
    h <- base::nrow(newdata)
  }

  #---------------- Build future data.frame ----------------

  # Create the index
  forecast_df <- tsibble::new_data(model$series, n = h)

  # Add events
  if(!base::is.null(model$parameters$events)){
    events <- NULL
    events <- model$parameters$events
    for(n in base::names(events)){
      forecast_df[n] <- 0
      forecast_df[base::which(forecast_df[,model$parameters$index , drop = TRUE] %in% events[[n]]), n] <- 1

    }
  }

  # Add knots
  if(!base::is.null(model$parameters$knots)){
    knots <- NULL
    knots <- model$parameters$knots
    for(n in base::names(knots)){
      start_point <- NULL
      start_point <- model$series[[n]][base::nrow( model$series)] + 1
      forecast_df[n] <- start_point:(start_point + base::nrow(forecast_df) - 1)

    }
  }

  #---------------- Setting the seasonal arguments----------------
  seasonal <- model$parameters$seasonal

  if(!base::is.null(seasonal)){
    if("minute" %in% seasonal){
      forecast_df$minute <- (lubridate::hour(forecast_df[[model$parameters$index]]) * 2 + (lubridate::minute(forecast_df[[model$parameters$index]]) + freq$value )/ freq$value) %>%
        base::factor(ordered = FALSE)
    }

    if("hour" %in% seasonal){
      forecast_df$hour <- (lubridate::hour(forecast_df[[model$parameters$index]]) + 1) %>% base::factor(ordered = FALSE)
    }

    if("wday" %in% seasonal){
      forecast_df$wday <- lubridate::wday(forecast_df[[model$parameters$index]], label = TRUE) %>% base::factor(ordered = FALSE)
    }

    if("yday" %in% seasonal){
      forecast_df$yday <- lubridate::yday(forecast_df[[model$parameters$index]]) %>% base::factor(ordered = FALSE)
    }

    if("week" %in% seasonal){
      forecast_df$week <- lubridate::week(forecast_df[[model$parameters$index]]) %>% base::factor(ordered = FALSE)
    }

    if("month" %in% seasonal){
      forecast_df$month <- lubridate::month(forecast_df[[model$parameters$index]], label = TRUE) %>% base::factor(ordered = FALSE)
    }

    if("quarter" %in% seasonal){
      forecast_df$quarter <- lubridate::quarter(forecast_df[[model$parameters$index]]) %>% base::factor(ordered = FALSE)
    }

  }

  #---------------- Setting the trend arguments ----------------
  trend <- trend_start <- trend_end <- NULL
  trend <- model$parameters$trend
  trend_start <- base::nrow(model$series) + 1
  trend_end <- trend_start + base::nrow(forecast_df) - 1

  if(base::is.numeric(trend$power)){
    for(i in trend$power){
      forecast_df[[base::paste("trend_power_", i, sep = "")]] <- c(trend_start:trend_end) ^ i
    }
  }

  if(trend$exponential){
    forecast_df$exp_trend <- base::exp(trend_start:trend_end)
  }

  if(trend$log){
    forecast_df$log_trend <- base::log(trend_start:trend_end)
  }

  if(trend$linear){
    forecast_df$linear_trend <- trend_start:trend_end
  }


  #---------------- Setting the init lags---------------
  if(!base::is.null(model$parameters$lags) && base::is.null(model$parameters$scale)){
    for(i in model$parameters$lags){
      forecast_df[[base::paste("lag_", i, sep = "")]] <- utils::tail(model$series[[model$parameters$y]], i)[1:base::nrow(forecast_df)]
    }
  } else if(!base::is.null(model$parameters$lags) && !base::is.null(model$parameters$scale)){
    if(!base::is.null(model$parameters$scale)){
      for(i in model$parameters$lags){
        forecast_df[[base::paste("lag_scale", i, sep = "")]] <- utils::tail(model$series[[base::paste("lag_scale", i, sep = "")]], i)[1:base::nrow(forecast_df)]
      }
    }
  }

  df_names <- base::names(forecast_df)

  if(!base::is.null(model$parameters$x) && !base::is.null(newdata)){
    forecast_df <- forecast_df %>% dplyr::left_join(newdata, by = model$parameters$index)
  }

  # If scale is NULL
  if(base::is.null(model$parameters$scale)){
    forecast_df$yhat <- NA
    # If lags are being used
    if(!base::is.null(model$parameters$lags)){
      for(i in 1:base::nrow(forecast_df)){
        for(p in base::seq_along(pi)){
          fit <- NULL
          fit <- stats::predict(model$model, newdata = forecast_df[i,],
                                se.fit = TRUE,
                                interval = "prediction",
                                level = pi[p])

          forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]][i] <- fit$fit[,"lwr"]
          forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]][i] <- fit$fit[,"upr"]
        }
        forecast_df$yhat[i] <- fit$fit[,"fit"]
        for(l in model$parameters$lags){
          if(i + l <= base::nrow(forecast_df)){
            forecast_df[[base::paste("lag_", l, sep = "")]][i + l] <- forecast_df$yhat[i]
          }
        }

      }
      # If lags are not being used
    } else {
      for(p in base::seq_along(pi)){
        fit <- NULL
        fit <- stats::predict(model$model, newdata = forecast_df,
                              se.fit = TRUE,
                              interval = "prediction",
                              level = pi[p])

        forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]] <- fit$fit[,"lwr"]
        forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]] <- fit$fit[,"upr"]
      }
      forecast_df$yhat <- fit$fit[,"fit"]
    }
    # If scale is not NULL
  } else if(!base::is.null(model$parameters$scale)){
    forecast_df$yhat <- NA

    # If lags are being used
    if(!base::is.null(model$parameters$lags)){
      for(i in 1:base::nrow(forecast_df)){
        for(p in base::seq_along(pi)){
          fit <- NULL
          fit <- stats::predict(model$model, newdata = forecast_df[i,],
                                se.fit = TRUE,
                                interval = "prediction",
                                level = pi[p])

          if(model$parameters$scale == "log"){
            forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]][i] <- base::exp(fit$fit[,"lwr"])
            forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]][i] <- base::exp(fit$fit[,"upr"])
            forecast_df$yhat[i] <- base::exp(fit$fit[,"fit"])
          } else if(model$parameters$scale == "normal"){
            forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]][i] <- fit$fit[,"lwr"] *
              (model$parameters$scaling_parameters$normal_max - model$parameters$scaling_parameters$normal_min) +
              model$parameters$scaling_parameters$normal_min

            forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]][i] <- fit$fit[,"upr"] *
            (model$parameters$scaling_parameters$normal_max - model$parameters$scaling_parameters$normal_min) +
              model$parameters$scaling_parameters$normal_min

            forecast_df$yhat[i] <-fit$fit[,"fit"] *
              (model$parameters$scaling_parameters$normal_max - model$parameters$scaling_parameters$normal_min) +
              model$parameters$scaling_parameters$normal_min

          } else if(model$parameters$scale == "standard"){
            forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]][i] <- fit$fit[,"lwr"] *
              model$parameters$scaling_parameters$standard_sd + model$parameters$scaling_parameters$standard_mean
            forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]][i] <- fit$fit[,"upr"]  *
              model$parameters$scaling_parameters$standard_sd + model$parameters$scaling_parameters$standard_mean
            forecast_df$yhat[i] <-fit$fit[,"fit"]  *
              model$parameters$scaling_parameters$standard_sd + model$parameters$scaling_parameters$standard_mean
          }
        }


        # Updating the lags values with new predictions
        for(l in model$parameters$lags){
          if(i + l <= base::nrow(forecast_df)){
            forecast_df[[base::paste("lag_scale", l, sep = "")]][i + l] <- fit$fit[,"fit"]
          }
        }

      }
      # If lags are not being used
    } else {
      for(p in base::seq_along(pi)){
        fit <- NULL
        fit <- stats::predict(model$model, newdata = forecast_df,
                              se.fit = TRUE,
                              interval = "prediction",
                              level = pi[p])
        if(model$parameters$scale == "log"){
        forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]] <- base::exp(fit$fit[,"lwr"])
        forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]] <- base::exp(fit$fit[,"upr"])
        } else if(model$parameters$scale == "normal"){
          forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]] <- fit$fit[,"lwr"] *
            (model$parameters$scaling_parameters$normal_max - model$parameters$scaling_parameters$normal_min) +
            model$parameters$scaling_parameters$normal_min
          forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]] <- fit$fit[,"upr"] *
            (model$parameters$scaling_parameters$normal_max - model$parameters$scaling_parameters$normal_min) +
            model$parameters$scaling_parameters$normal_min
        } else if(model$parameters$scale == "standard"){
          forecast_df[[base::paste("lower", 100 * pi[p], sep = "")]] <- fit$fit[,"lwr"] *
            model$parameters$scaling_parameters$standard_sd + model$parameters$scaling_parameters$standard_mean
          forecast_df[[base::paste("upper", 100 * pi[p], sep = "")]] <- fit$fit[,"upr"] *
            model$parameters$scaling_parameters$standard_sd + model$parameters$scaling_parameters$standard_mean
        }
      }

      if(model$parameters$scale == "log"){
      forecast_df$yhat <- base::exp(fit$fit[,"fit"])
      } else if(model$parameters$scale == "normal"){
        forecast_df$yhat <- fit$fit[,"fit"] *
          (model$parameters$scaling_parameters$normal_max - model$parameters$scaling_parameters$normal_min) +
          model$parameters$scaling_parameters$normal_min
      } else if(model$parameters$scale == "standard"){
        forecast_df$yhat <- fit$fit[,"fit"] *
          model$parameters$scaling_parameters$standard_sd + model$parameters$scaling_parameters$standard_mean
      }
    }

  }


  pi_lower <- 100 * base::sort(pi, decreasing = TRUE)
  pi_upper <- 100 * base::sort(pi, decreasing = FALSE)
  output <- base::list(model = model$model,
                       parameters = base::list(h = h,
                                               pi = pi,
                                               scale = model$parameters$scale,
                                               y = model$parameters$y,
                                               x = model$parameters$x,
                                               index = model$parameters$index),
                       actual = model$series,
                       forecast = tsibble::as_tsibble(forecast_df[, c(df_names, base::paste0("lower", pi_lower), "yhat", c(base::paste0("upper", pi_upper)))],
                                                      index = model$parameters$index))

  final_output <- base::structure(output, class = "forecastLM")
  return(final_output)

}
