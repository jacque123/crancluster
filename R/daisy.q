#### $Id: daisy.q,v 1.6 2002/03/04 10:44:45 maechler Exp maechler $
daisy <-
function(x, metric = c("euclidean","manhattan"), stand = FALSE, type = list())
{
    ## check type of input matrix
    if(length(dx <- dim(x)) != 2 || !(is.data.frame(x) || is.numeric(x)))
        stop("x is not a dataframe or a numeric matrix.")
    if(length(type)) {
        tA <- type$asymm
        tS <- type$symm
        if((!is.null(tA) || !is.null(tS))) {
            d.bin <- as.data.frame(x[,c(tA,tS), drop = FALSE])
            if(!all(sapply(lapply(d.bin, function(y)
                                  levels(as.factor(y))), length) == 2))
                stop("at least one binary variable has more than 2 levels.")
            ## Convert factors to integer, such that ("0","1") --> (0,1):
            if(any(is.f <- sapply(d.bin, is.factor)))
                d.bin[is.f] <- lapply(d.bin[is.f],
                                      function(f) as.integer(as.character(f)))
            if(!all(sapply(d.bin, function(y)
                           is.logical(y) ||
                           all(sort(unique(as.numeric(y[!is.na(y)])))==0:1))))
                stop("at least one binary variable has values other than 0,1, and NA")
        }
    }
    ## transform variables and construct `type' vector
    n <- dx[1]# nrow
    p <- dx[2]# ncol
    if(is.data.frame(x)) {
        type2 <- sapply(x, data.class)
        x <- data.matrix(x)
    } else type2 <- rep("numeric", p)
    if(length(type)) {
        if(!is.list(type)) stop("invalid `type'; must be named list")
        tT <- type$ ordratio
        tL <- type$ logratio
        x[, names(type2[tT])] <- codes(as.ordered(x[, names(type2[tT])]))
        x[, names(type2[tL])] <- log10(           x[, names(type2[tL])])
        type2[tA] <- "A"
        type2[tS] <- "S"
        type2[tT] <- "T" # was "O" (till 2000-12-14) accidentally !
    }
    type2[tI <- type2 %in% c("numeric", "integer") ] <- "I"
    if(any(tI) && any(iBin <- apply(x[,tI, drop = FALSE],2,
                                    function(v) length(table(v)) == 2)))
        warning("binary variable(s) ", paste(which(tI)[iBin], collapse=","),
                " treated as interval scaled")

    type2[type2 == "ordered"] <- "O"
    type2[type2 == "factor"] <- "N"
    if(any(ilog <- type2 == "logical")) {
        warning("setting `logical' variable",if(sum(ilog)>1)"s " else " ",
                which(ilog), " to type `asymm'")
        type2[ilog] <- "A"
    }
    ## standardize, if necessary
    if(all(type2 == "I")) {
        if(stand)
            x <- scale(x, scale = apply(x, 2,
                          function(y)
                          mean(abs(y - mean(y, na.rm = TRUE)), na.rm = TRUE)))
        jdat <- 2
        metric <- match.arg(metric)
        ndyst <- if(metric == "manhattan") 2 else 1
    }
    else { ## mixed case
        if(!missing(metric))
            warning("`metric' is not used with mixed variables")
        colmin   <- apply(x, 2, min, na.rm = TRUE)
        colrange <- apply(x, 2, max, na.rm = TRUE) - colmin
        x <- scale(x, center = colmin, scale = colrange)
        jdat <- 1
        ndyst <- 0
    }
    ## 	type2 <- paste(type2, collapse = "")
    typeCodes <- c('A','S','N','O','I','T')
    type3 <- match(type2, typeCodes)# integer
    if(any(ina <- is.na(type3)))
        stop("invalid type", type2[ina],"  for column numbers", which(is.na))
    ## put info about NAs in arguments for the Fortran call
    jtmd <- ifelse(is.na(rep(1, n) %*% x), -1, 1)
    jtmd[type3 <= 2] <- 0# for the binary ones -- new in 1.5-1 (May 2002)!
    valmisdat <- min(x, na.rm = TRUE) - 0.5
    x[is.na(x)] <- valmisdat
    valmd <- rep(valmisdat, p)
    ## call Fortran routine
    storage.mode(x) <- "double"
    storage.mode(valmd) <- "double"
    storage.mode(jtmd) <- "integer"

    disv <- .Fortran("daisy",
                     n,
                     p,
                     x,
                     valmd,
                     jtmd,
                     as.integer(jdat),
                     type3,             # vtype
                     as.integer(ndyst),
                     dis = double(1 + (n * (n - 1))/2),
                     DUP = FALSE,
                     PACKAGE = "cluster")$dis[-1]
    ## adapt Fortran output to S:
    ## convert lower matrix, read by rows, to upper matrix, read by rows.
    disv[disv == -1] <- NA
    full <- matrix(0, n, n)
    full[!lower.tri(full, diag = TRUE)] <- disv
    disv <- t(full)[lower.tri(full)]
    ## give warning if some dissimilarities are missimg
    if(is.na(min(disv))) attr(disv, "NA.message") <-
        "NA-values in the dissimilarity matrix !"
    ## construct S object -- "dist" methods are *there* !
    class(disv) <- c("dissimilarity", "dist")
    attr(disv, "Labels") <- dimnames(x)[[1]]
    attr(disv, "Size") <- n
    attr(disv, "Metric") <- ifelse(!ndyst, "mixed", metric)
    if(!ndyst) attr(disv, "Types") <- typeCodes[type3]
    disv
}

print.dissimilarity <- function(x, ...)
{
    cat("Dissimilarities :\n")
    print(as.vector(x), ...)
    cat("\n")
    if(!is.null(attr(x, "na.message")))
        cat("Warning : ", attr(x, "NA.message"), "\n")
    cat("Metric : ", attr(x, "Metric"),
        if(!is.null(aT <- attr(x,"Types")))
        paste(";  Types =", paste(aT, collapse=", ")), "\n")
    cat("Number of objects : ", attr(x, "Size"), "\n", sep="")
    invisible(x)
}

summary.dissimilarity <- function(object, ...)
{
    cat(length(object), "dissimilarities, summarized :\n")
    print(sx <- summary(as.vector(object), ...))
    ## now exactly as print.<class> :
    cat("\n")
    if(!is.null(attr(object, "na.message")))
        cat("Warning : ", attr(object, "NA.message"), "\n")
    cat("Metric : ", attr(object, "Metric"),
        if(!is.null(aT <- attr(object,"Types")))
        paste(";  Types =", paste(aT, collapse=", ")), "\n")
    cat("Number of objects : ", attr(object, "Size"), "\n", sep="")
    invisible(sx)
}
