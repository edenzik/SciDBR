#
#    _____      _ ____  ____
#   / ___/_____(_) __ \/ __ )
#   \__ \/ ___/ / / / / __  |
#  ___/ / /__/ / /_/ / /_/ / 
# /____/\___/_/_____/_____/  
#
#
#
# BEGIN_COPYRIGHT
#
# This file is part of SciDB.
# Copyright (C) 2008-2014 SciDB, Inc.
#
# SciDB is free software: you can redistribute it and/or modify
# it under the terms of the AFFERO GNU General Public License as published by
# the Free Software Foundation.
#
# SciDB is distributed "AS-IS" AND WITHOUT ANY WARRANTY OF ANY KIND,
# INCLUDING ANY IMPLIED WARRANTY OF MERCHANTABILITY,
# NON-INFRINGEMENT, OR FITNESS FOR A PARTICULAR PURPOSE. See
# the AFFERO GNU General Public License for the complete license terms.
#
# You should have received a copy of the AFFERO GNU General Public License
# along with SciDB.  If not, see <http://www.gnu.org/licenses/agpl-3.0.html>
#
# END_COPYRIGHT
#

# cf glm.fit
glm.fit_scidb = function(x,y,weights=NULL,family=gaussian(),intercept)
{
  nobs = length(y)
  got_glm = length(grep("glm",.scidbenv$ops[,2]))>0
  if(missing(intercept)) intercept=0
  intercept = as.numeric(intercept)
  xchunks = as.numeric(scidb_coordinate_chunksize(x))
  if(missing(`weights`)) `weights`=NULL
  if(is.numeric(`weights`))
  {
    `weights` = as.scidb(as.double(weights),chunkSize=xchunks[1])
  } else
  {
    weights = build(1.0,nrow(x),start=as.numeric(scidb_coordinate_start(x)[1]),chunksize=xchunks[1])
  }
  if(!is.scidb(y))
  {
    y = as.scidb(y)
  }
  if(!got_glm)
  {
    stop("The Paradigm4 glm operator was not found.")
  }
  x = substitute(x)
  y = substitute(y)
  `weights` = substitute(`weights`)
  dist = family$family
  link = family$link
# GLM has a some data partitioning requirements to look out for:
  if(xchunks[2]<dim(x)[2])
  {
    x = repart(x,chunk=c(xchunks[1],dim(x)[2]))
  }
  xchunks = as.numeric(scidb_coordinate_chunksize(x))
  ychunks = as.numeric(scidb_coordinate_chunksize(y))
  if((ychunks[1] != xchunks[1]) )
  {
    y = repart(y, chunk=xchunks[1])
  }
  query = sprintf("glm(%s,%s,%s,'%s','%s')",
           x@name, y@name, weights@name, dist, link)
  M = .scidbeval(query,eval=TRUE,gc=TRUE)
  m1 = M[,0][] # Cache 1st column
  ans = list(
    coefficients = M[0,],
    stderr = M[1,],
    tval = M[2,],
    pval = M[3,],
    aic = m1[12],
    null.deviance = m1[13],
    res.deviance = m1[15],
    dispersion = m1[5],
    df.null = m1[6] - intercept,
    df.residual = m1[7],
    converged = m1[10]==1,
    totalObs = m1[8],
    nOK = m1[9],
    loglik = m1[14],
    rss = m1[16],
    iter = m1[18],
    weights = weights,
    family = family,
    y = y,
    x = x
  )
# BUG HERE IN SCIDB GLM AFFECTING binomial and poisson families?
# FIXED IN SciDB 14.3
  if(compare_versions(options("scidb.version")[[1]],14.3))
  {
    return (ans)
  }
  if(dist=="binomial" || dist=="poisson")
  {
    ans$scidb_pval = ans$pval
    ans$pval = 2*pnorm(-abs(ans$tval[]))
  }
  ans
}



# A really basic prototype glm function, limited to simple formulas and
# treatment contrast encoding. cf glm.
glm_scidb = function(formula, data, family=gaussian(), weights=NULL)
{
  if(!is.scidbdf(data)) stop("data must be a scidbdf object")
  if(is.character(formula)) formula=as.formula(formula)
  M = model_scidb(formula, data)
  ans = glm.fit(M$model, M$response, weights=weights, family=family,intercept=M$intercept)
  ans$formula = M$formula
  ans$coefficient_names = M$names
  ans$call = match.call()
  class(ans) = "glm_scidb"
  ans
}

.format = function(x)
{
  o = options(digits=4)
  ans = paste(capture.output(x),collapse="\n")
  options(o)
  ans
}

# cf print.glm
print.glm_scidb = function(x, ...)
{
  ans = "Call:"
  ans = paste(ans,.format(x$call),sep="\n")
  ans = paste(ans,"Formula that was used:",sep="\n\n")
  ans = paste(ans,.format(x$formula),sep="\n")
  ans = paste(ans,.format(x$family),sep="\n")

  cfs = coef(x)[]
  names(cfs) = x$coefficient_names
  ans = paste(ans,"Coefficients:",sep="\n")
  ans = paste(ans,.format(cfs),sep="\n\n")
  ans = paste(ans,sprintf("Null deviance: %.2f on %d degrees of freedom",x$null.deviance, x$df.null),sep="\n\n")
  ans = paste(ans,sprintf("Residual deviance: %.2f on %d degrees of freedom",x$res.deviance, x$df.residual),sep="\n")
  ans = paste(ans,sprintf("AIC: %.1f",x$aic),sep="\n")
  cat(ans,"\n")
}

# cf summary.glm
summary.glm_scidb = function(object, ...)
{
  x = object
  ans = "Call:"
  ans = paste(ans,.format(x$call),sep="\n")
  ans = paste(ans,"Formula that was used:",sep="\n\n")
  ans = paste(ans,.format(x$formula),sep="\n")
  ans = paste(ans,.format(x$family),sep="\n")

# Coefficient table
  tbl_coef = coef(x)[]
  tbl_stderr = x$stderr[]
  tbl_zval = x$tval[]
  p = x$pval[]
  sig = c("***","**","*",".","")
  star = sig[as.integer(cut(p,breaks=c(0,0.001,0.01,0.05,0.1,1)))]
  tbl = data.frame(tbl_coef, tbl_stderr, tbl_zval, p, star)
  colnames(tbl) = c("Estimate", "Std. Error", "z value", "Pr(>|z|)","")
  rownames(tbl) = x$coefficient_names
  ans = paste(ans,.format(tbl),sep="\n\n")
  ans = paste(ans,"---\nSignif. codes:  0 *** 0.001 ** 0.01 * 0.05 . 0.1   1",sep="\n")
  ans = paste(ans,sprintf("Dispersion parameter: %.2f",x$dispersion),sep="\n\n")
  ans = paste(ans,sprintf("Null deviance: %.2f on %d degrees of freedom",x$null.deviance, x$df.null),sep="\n\n")
  ans = paste(ans,sprintf("Residual deviance: %.2f on %d degrees of freedom",x$res.deviance, x$df.residual),sep="\n")
  ans = paste(ans,sprintf("AIC: %.1f",x$aic),sep="\n")
  ans = paste(ans,sprintf("Number of Fisher Scoring iterations: %d",x$iter),sep="\n")
  cat(ans,"\n")
}

# A limited version of a model matrix builder for linear models,
# cf model.matrix and model.frame. Returns a model matrix for the scidbdf
# object and the formula. String-valued variables in data are converted to
# treatment contrasts, and if present a sparse model matrix is returned.
# Returns a list of:
# formula: The (possibly modified) formula associated with the model matrix
# model:    A SciDB matrix with a single attribute named 'val' (model matrix)
# response: A SciDB vector holding the response variable values
# formual:  The formula
# names:    The names of the model variables corresponding to the
#           columns of 'model'
# intercept: TRUE if an intercept term is present
model_scidb = function(formula, data)
{
  tryCatch(iquery("load_library('collate')"),
    error=function(e) stop("This function requires the collate operator.\n See https://github.com/Paradigm4/collate"))
  if(!is.scidbdf(data)) stop("data must be a scidbdf object")
  if(is.character(formula)) formula=as.formula(formula)
  dummy = data.frame(matrix(NA,ncol=length(scidb_attributes(data))))
  names(dummy) = scidb_attributes(data)
  t = terms(formula, data=dummy)
  f = attr(t,"factors")
  v = attr(t,"term.labels")
  i = attr(t,"intercept")
  r = attr(t,"response")

  iname = c()
  if(i==1)
  {
# Add an intercept term
    iname = scidb:::make.unique_(data@attributes,"intercept")
    data = bind(data, iname, "double(1)")
  }

  response = project(data,rownames(f)[r])
  types = scidb:::scidb_types(data)
  a = scidb_attributes(data)
  factors = c()  # Will contain a list of factor variables
  vars = c()     # Will contain a list of continuous variables
# Check for unsupported formulae and warn.
  ok = v %in% data@attributes
  if(!all(ok))
  {
    not_supported = paste(v[!ok], collapse=",")
    warning("Your formula is too complicated for this method. The following variables are not explicitly available and were not used in the model: ",not_supported)
    formula = formula(drop.terms(t, which(v %in% not_supported), keep.response=TRUE))
  }
  w = which(data@attributes %in% c(v,iname))
  if(length(w)<1) stop("No variables to model on")
  for(j in w)
  {
    if(types[j]=="string")
    {
# Create a factor
      factors = c(factors,unique(project(data,j)))
      names(factors)[length(factors)] = a[j]
      next
    }
    if(types[j]!="double")
    {
# Coerce to a double value
      d = scidb:::make.unique_(a, sprintf("%s_double",a[j]))
      expr = sprintf("double(%s)", a[j])
      data = bind(data, d, expr)
      vars = c(vars, d)
      next
    }
    vars = c(vars, a[j])
  }

  varsstr = paste(vars, collapse=",")
  query = sprintf("collate(project(%s,%s))",data@name,varsstr)
  M = scidb:::.scidbeval(query,gc=TRUE,eval=TRUE)

  if(length(factors)<1) return(list(formula=formula,model=M,response=response,names=vars,intercept=(i==1)))

# Repartition to accomodate the factor contrasts, subtracting one
# if an intercept term is present (i).
  contrast_dim = 0
  for(j in factors)
  {
    contrast_dim = contrast_dim + count(j) - i
  }

  newdim = ncol(M) + contrast_dim
  newend = c(nrow(M)-1, newdim - 1)
  newchunk = c(ceiling(1e6/newdim),newdim)

  schema = sprintf("%s%s",scidb:::build_attr_schema(M),
    scidb:::build_dim_schema(M,newstart=c(0,0),newend=newend,newchunk=newchunk))
  M = reshape(M, shape=c(nrow(M), ncol(M)))  # Reset origin without moving data
  M = redimension(M,schema=schema)           # Redimension to get extra columns

# Merge in the contrasts
  col = length(vars)
  varnames = vars
  for(j in 1:length(factors))
  {
    dn = scidb:::make.unique_(dimensions(data), "i")    # Naming conflicts are a big PITA
    n  = names(factors)[j]
    idx = sprintf("%s_index",n)
    idx = scidb:::make.unique_(data@attributes, idx)
    y = project(index_lookup(data, factors[[j]], n, idx), idx)
    one = scidb:::make.unique_(y@attributes, "val")
    column = scidb:::make.unique_(y@attributes, "j")
    N = sprintf("%s%s",names(factors)[j],iquery(factors[[j]],return=TRUE)[,2])
    if(i>0)
    {
# Intercept term present
      y = subset(y, sprintf("%s > 0",idx))
      y = bind(y, c(one,column), c("double(1)",sprintf("int64(%s + %d - 1)",idx,col)))
      varnames = c(varnames, N[-1])
      col = col + length(N) - 1
    } else
    {
# No intercept term
      y = bind(y, c(one,column), c("double(1)",sprintf("int64(%s + %d)",idx,col)))
      varnames = c(varnames, N)
      col = col + length(N)
    }
    schema = sprintf("%s%s",
             scidb:::build_attr_schema(y,newnames=c("index","val","j")),
             scidb:::build_dim_schema(y,newnames="i"))
    y = redimension(reshape(cast(y,schema),shape=nrow(y)),M)
# ... merge into M
    M = merge(M,y,merge=TRUE) # eval this?
  }

  return(list(formula=formula,model=M,response=response,names=varnames,intercept=(i==1)))
}
