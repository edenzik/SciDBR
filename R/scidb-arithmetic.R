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

# Element-wise operations
Ops.scidb = function(e1,e2) {
  switch(.Generic,
    '^' = .binop(e1,e2,"^"),
    '+' = .binop(e1,e2,"+"),
    '-' = .binop(e1,e2,"-"),
    '*' = .binop(e1,e2,"*"),
    '/' = .binop(e1,e2,"/"),
    '<' = .compare(e1,e2,"<"),
    '<=' =.compare(e1,e2,"<="),
    '>' = .compare(e1,e2,">"),
    '>=' = .compare(e1,e2,">="),
    '==' = .compare(e1,e2,"="),
    '!=' = .compare(e1,e2,"<>"),
    default = stop("Unsupported binary operation.")
  )
}

# e1 and e2 must each already be SciDB arrays.
scidbmultiply = function(e1,e2)
{
# As of SciDB version 13.12, SciDB exhibits nasty bugs when gemm is nested
# within other SciDB operators, in particular subarray. We use sg to avoid
# this problem.
  GEMM.BUG = ifelse(is.logical(options("scidb.gemm_bug")[[1]]),options("scidb.gemm_bug")[[1]],FALSE)
  `eval` = FALSE
# Check for availability of spgemm
  SPGEMM = length(grep("spgemm",.scidbenv$ops[,2]))>0
  a1 = .get_attribute(e1)
  a2 = .get_attribute(e2)
  e1.sparse = is.sparse(e1)
  e2.sparse = is.sparse(e2)
  SPARSE = e1.sparse || e2.sparse

# Up to at least SciDB 13.12, gemm does not accept nullable attributes.
# XXX This restriction needs to be changed in a future SciDB release.
  miswarn = "This array might contain missing values (R NA/SciDB 'null').\n Missing values are not yet understood by SciDB multiplication operators.\n Missing values, if any, have been replaced with zero."
  if(any(scidb_nullable(e1)))
  {
    warning(miswarn)
    e1 = substitute(e1)
  }
  if(any(scidb_nullable(e2)))
  {
    warning(miswarn)
    e2 = substitute(e2)
  }

# Promote vectors to row- or column-vectors as required.
  if(length(dim(e1))<2)
  {
    e2len = as.numeric(scidb_coordinate_bounds(e2)$length)
    e1chunk = scidb_coordinate_chunksize(e1)
    e2chunk = scidb_coordinate_chunksize(e2)
    L = dim(e1)
    M = L/e2len[1]
    if(M != floor(M)) stop("Non-conformable dimensions")

    as = build_attr_schema(e1)
    osc = sprintf("%s[i=0:%s,%s,0,j=0:%s,%s,0]",
            as, noE(M-1), noE(e1chunk[1]),
              noE(e2len[1]-1), noE(e2chunk[1]))
    e1 = reshape(e1, schema=osc)
  }
  if(length(dim(e2)) < 2)
  {
    e1len = as.numeric(scidb_coordinate_bounds(e1)$length)
    e1chunk = scidb_coordinate_chunksize(e1)
    e2chunk = scidb_coordinate_chunksize(e2)
    L = dim(e2)
    N = L/e1len[2]
    if(N != floor(N)) stop("Non-conformable dimensions")

    as = build_attr_schema(e2)
    osc = sprintf("%s[i=0:%s,%s,0,j=0:%s,%s,0]",
            as, noE(e1len[2]-1), noE(e1chunk[2]),
                     noE(N-1), noE(e2chunk[1]))
    e2 = reshape(e2, schema=osc)
  }

# We use subarray to handle starting index mismatches (subarray
# returns an array with dimension indices starting at zero).
  l1 = length(dim(e1))
  lb = paste(rep("null",l1),collapse=",")
  ub = paste(rep("null",l1),collapse=",")
  if(GEMM.BUG) op1 = sprintf("sg(subarray(%s,%s,%s),1,-1)",e1@name,lb,ub)
  else op1 = sprintf("subarray(%s,%s,%s)",e1@name,lb,ub)
  l2 = length(dim(e2))
  lb = paste(rep("null",l2),collapse=",")
  ub = paste(rep("null",l2),collapse=",")
  if(GEMM.BUG) op2 = sprintf("sg(subarray(%s,%s,%s),1,-1)",e2@name,lb,ub)
  else op2 = sprintf("subarray(%s,%s,%s)",e2@name,lb,ub)

  if(!SPARSE)
  {
# Adjust the arrays to conform to GEMM requirements
    dnames = make.names_(c(dimensions(e1)[[1]],dimensions(e2)[[2]]))
    CHUNK_SIZE = options("scidb.gemm_chunk_size")[[1]]
    op1 = sprintf("repart(%s,<%s:%s>[%s=0:%s,%s,0,%s=0:%s,%s,0])",op1,a1,scidb_types(e1)[1],
            dimensions(e1)[1],noE(as.numeric(scidb_coordinate_end(e1)[1])),noE(CHUNK_SIZE),
            dimensions(e1)[2],noE(as.numeric(scidb_coordinate_end(e1)[2])),noE(CHUNK_SIZE))
    op2 = sprintf("repart(%s,<%s:%s>[%s=0:%s,%s,0,%s=0:%s,%s,0])",op2,a2,scidb_types(e2)[1],
            dimensions(e2)[1],noE(as.numeric(scidb_coordinate_end(e2)[1])),noE(CHUNK_SIZE),
            dimensions(e2)[2],noE(as.numeric(scidb_coordinate_end(e2)[2])),noE(CHUNK_SIZE))
    osc = sprintf("<%s:%s>[%s=0:%s,%s,0,%s=0:%s,%s,0]",a1,scidb_types(e1)[1],
              dnames[[1]],noE(as.numeric(scidb_coordinate_end(e1)[1])),noE(CHUNK_SIZE),
              dnames[[2]],noE(as.numeric(scidb_coordinate_end(e2)[2])),noE(CHUNK_SIZE))
    op3 = sprintf("build(%s,0)",osc)
  } else
  {
# Adjust array partitions as required by spgemm
    op2 = sprintf("repart(%s, <%s:%s>[%s=0:%s,%s,0,%s=0:%s,%s,0])",
            op2, a2, scidb_types(e2)[1],
            dimensions(e2)[1],noE(as.numeric(scidb_coordinate_end(e2)[1])),
                              noE(scidb_coordinate_chunksize(e1)[2]),
            dimensions(e2)[2], noE(as.numeric(scidb_coordinate_end(e2)[2])),
                              noE(scidb_coordinate_chunksize(e2)[2]))
  }

# Decide which multiplication algorithm to use
  if(SPARSE && !SPGEMM)
  {
    stop("Sparse matrix multiplication not supported")
  }
  else if (SPARSE && SPGEMM)
  {
    query = sprintf("spgemm(%s, %s)", op1, op2)
  }
  else
  {
    query = sprintf("gemm(%s, %s, %s)",op1,op2,op3)
    if(GEMM.BUG) query = sprintf("sg(gemm(%s, %s, %s),1,-1)",op1,op2,op3)
  }
  ans = .scidbeval(query,gc=TRUE,eval=eval,depend=list(e1,e2))
  ans
}

# Element-wise binary operations
.binop = function(e1,e2,op)
{
  e1s = e1
  e2s = e2
  e1a = "scalar"
  e2a = "scalar"
  dnames = c()
  depend = c()
# Check for non-scidb object arguments and convert to scidb
  if(!inherits(e1,"scidb") && length(e1)>1) {
    x = tmpnam()
    e1 = as.scidb(e1,name=x,gc=TRUE)
  }
  if(!inherits(e2,"scidb") && length(e2)>1) {
    x = tmpnam()
    e2 = as.scidb(e2,name=x,gc=TRUE)
  }
  if(inherits(e1,"scidb"))
  {
#    e1 = scidbeval(e1,gc=TRUE)
    e1 = make_nullable(e1)
    e1a = .get_attribute(e1)
    depend = c(depend, e1)
    dnames = c(dnames, dimensions(e1))
  }
  if(inherits(e2,"scidb"))
  {
#    e2 = scidbeval(e2,gc=TRUE)
    e2 = make_nullable(e2)
    e2a = .get_attribute(e2)
    depend = c(depend, e2)
    dnames = c(dnames, dimensions(e2))
  }
# OK, we've got two scidb arrays, op them. v holds the new attribute name.
  v = make.unique_(c(e1a,e2a,dnames),"v")

# We use subarray to handle starting index mismatches...
  q1 = q2 = ""
  l1 = length(dim(e1))
  lb = paste(rep("null",l1),collapse=",")
  ub = paste(rep("null",l1),collapse=",")
  GEMM.BUG = ifelse(is.logical(options("scidb.gemm_bug")[[1]]),options("scidb.gemm_bug")[[1]],FALSE)
  if(inherits(e1,"scidb"))
  {
    if(GEMM.BUG) q1 = sprintf("sg(subarray(project(%s,%s),%s,%s),1,-1)",e1@name,e1a,lb,ub)
    else q1 = sprintf("subarray(project(%s,%s),%s,%s)",e1@name,e1a,lb,ub)
  }
  l = length(dim(e2))
  lb = paste(rep("null",l),collapse=",")
  ub = paste(rep("null",l),collapse=",")
  if(inherits(e2,"scidb"))
  {
    if(GEMM.BUG) q2 = sprintf("sg(subarray(project(%s,%s),%s,%s),1,-1)",e2@name,e2a,lb,ub)
    else q2 = sprintf("subarray(project(%s,%s),%s,%s)",e2@name,e2a,lb,ub)
  }
# Adjust the 2nd array to be schema-compatible with the 1st:
  if(l==2 && l1==2)
  {
    e2names = dimensions(e2)
    bounds  = scidb_coordinate_bounds(e2)
    e2end = bounds$end
    e1chunk = scidb_coordinate_chunksize(e1)
    e1overlap = scidb_coordinate_overlap(e1)
    schema = sprintf(
       "%s[%s=0:%s,%s,%s,%s=0:%s,%s,%s]",
       build_attr_schema(e2,I=1),
       e2names[1], noE(e2end[1]), noE(e1chunk[1]), noE(e1overlap[1]),
       e2names[2], noE(e2end[2]), noE(e1chunk[2]), noE(e1overlap[2]))
    q2 = sprintf("repart(%s, %s)", q2, schema)

# Handle sparsity by cross-merging data (full outer join):
    if(l==l1)
    {
      if(is.sparse(e1))
      {
        q1 = sprintf("merge(%s,cast(project(apply(%s,__zero__,%s(0)),__zero__),<__zero__:%s null>%s))",q1,q2,scidb_types(e1),scidb_types(e1), build_dim_schema(e1))
      }
      if(is.sparse(e2))
      {
        q2 = sprintf("merge(%s,cast(project(apply(%s,__zero__,%s(0)),__zero__),<__zero__:%s null>%s))",q2,q1,scidb_types(e2),scidb_types(e2), build_dim_schema(e2))
      }
    }
  }
  p1 = p2 = ""
# Syntax sugar for exponetiation (map the ^ infix operator to pow):
  if(op=="^")
  {
    p1 = "pow("
    op = ","
    p2 = ")"
  }
# Handle special scalar multiplication case:
  if(length(e1s)==1)
    Q = sprintf("apply(%s,%s, %s %.15f %s %s %s)",q2,v,p1,e1s,op,e2a,p2)
  else if(length(e2s)==1)
    Q = sprintf("apply(%s,%s,%s %s %s %.15f %s)",q1,v,p1,e1a,op,e2s,p2)
  else if(l1==1 && l==2)
  {
# Handle special case similar to, but a bit different than vector recylcing.
# This case requires a dimensional match along the 1st dimensions, and it's
# useful for matrix row scaling. This is limited to vectors that match the
# number of rows of the array.
# First, conformably redimension e1
    newschema = build_dim_schema(e2,I=1,newnames=dimensions(e1)[1])
    re1 = sprintf("redimension(%s,%s%s)",q1,build_attr_schema(e1),newschema)
    Q = sprintf("cross_join(%s as e2, %s as e1, e2.%s, e1.%s)", q2, re1, dimensions(e2)[1], dimensions(e1)[1])
    Q = sprintf("apply(%s, %s, %s e1.%s %s e2.%s %s)", Q,v,p1,e1a,op,e2a,p2)
  }
  else if(l1==2 && l==1)
  {
# Handle special case similar to, but a bit different than vector recylcing.
# This case requires a dimensional match along the 2nd dimension, and it's
# useful for matrix column scaling. This is not R standard but very useful.
# First, conformably redimension e2.
    newschema = build_dim_schema(e1,I=2,newnames=dimensions(e2)[1])
    re2 = sprintf("redimension(%s,%s%s)",q2,build_attr_schema(e2),newschema)
    Q = sprintf("cross_join(%s as e1, %s as e2, e1.%s, e2.%s)", q1, re2, dimensions(e1)[2], dimensions(e2)[1])
    Q = sprintf("apply(%s, %s, %s e1.%s %s e2.%s %s)", Q,v,p1,e1a,op,e2a,p2)
  }
  else
  {
    Q = sprintf("join(%s as e1, %s as e2)", q1, q2)
    Q = sprintf("apply(%s, %s, %s e1.%s %s e2.%s %s)", Q,v,p1,e1a,op,e2a,p2)
  }
  Q = sprintf("project(%s, %s)",Q,v)
  .scidbeval(Q, eval=FALSE, gc=TRUE, depend=depend)
}

# Very basic comparisons. See also filter.
# e1: A scidb array
# e2: A scalar or a scidb array. If a scidb array, the return
# .joincompare(e1,e2,op) (q.v.)
# op: A comparison infix operator character
#
# Return a scidb object
# Can throw a query error.
.compare = function(e1,e2,op,traditional)
{
  if(missing(traditional)) traditional=TRUE
  if(!(inherits(e1,"scidb") || inherits(e1,"scidbdf"))) stop("Sorry, not yet implemented.")
  if(inherits(e2,"scidb")) return(.joincompare(e1,e2,op))
  op = gsub("==","=",op,perl=TRUE)
# Automatically quote characters
  if(is.character(e2)) e2 = sprintf("'%s'",e2)
  q1 = paste(paste(e1@attributes,op,e2),collapse=" and ")
# Traditional R comparisons return an array of the same shape with a true/false
# value.
  if(traditional)
  {
    newattr = make.unique_(e1@attributes, "condition")
    query = sprintf("project(apply(%s, %s, %s), %s)", e1@name, newattr, q1, newattr)
    return(.scidbeval(query, eval=FALSE, gc=TRUE, depend=list(e1)))
  }
# Alternate comparisons return a sparse mask
  query = sprintf("filter(%s, %s)", e1@name, q1)
  .scidbeval(query, eval=FALSE, gc=TRUE, depend=list(e1))
}

.joincompare = function(e1,e2,op)
{
  stop("Yikes! Not implemented yet...")
}

tsvd = function(x,nu,tol=0.0001,maxit=20)
{
  m = ceiling(1e6/nrow(x))
  n = ceiling(1e6/ncol(x))
  schema = sprintf("[%s=0:%s,%s,0,%s=0:%s,%s,0]",
                     dimensions(x)[1], noE(nrow(x)-1), noE(m),
                     dimensions(x)[2], noE(ncol(x)-1), noE(ncol(x)))
  tschema = sprintf("[%s=0:%s,%s,0,%s=0:%s,%s,0]",
                     dimensions(x)[2], noE(ncol(x)-1), noE(n),
                     dimensions(x)[1], noE(nrow(x)-1), noE(nrow(x)))
  schema = sprintf("%s%s",build_attr_schema(x), schema)
  tschema = sprintf("%s%s",build_attr_schema(x), tschema)
  query  = sprintf("tsvd(redimension(unpack(%s,row),%s), redimension(unpack(transpose(%s),row),%s), %.0f, %f, %.0f)", x@name, schema, x@name, tschema, nu,tol,maxit)
  narray = .scidbeval(query, eval=TRUE, gc=TRUE)
  ans = list(u=slice(narray, "matrix", 0,eval=FALSE)[,between(0,nu-1)],
             d=slice(narray, "matrix", 1,eval=FALSE)[between(0,nu-1),between(0,nu-1)],
             v=slice(narray, "matrix", 2,eval=FALSE)[between(0,nu-1),],
             narray=narray)
  attr(ans$u,"sparse") = TRUE
  attr(ans$d,"sparse") = TRUE
  attr(ans$v,"sparse") = TRUE
  ans
}

svd_scidb = function(x, nu=min(dim(x)), nv=nu)
{
  got_tsvd = length(grep("tsvd",.scidbenv$ops[,2]))>0
  if(missing(nu)) nu = min(dim(x))
  if(!is.sparse(x) && (nu > (min(dim(x))/3)) || !got_tsvd)
  {
# Compute the full SVD
    u = tmpnam()
    d = tmpnam()
    v = tmpnam()
    xend = scidb_coordinate_end(x)
    schema = sprintf("[%s=0:%s,1000,0,%s=0:%s,1000,0]",
                     dimensions(x)[1],noE(xend[1]),
                     dimensions(x)[2],noE(xend[2]))
    schema = sprintf("%s%s",build_attr_schema(x),schema)
    iquery(sprintf("store(gesvd(repart(%s,%s),'left'),%s)",x@name,schema,u))
    iquery(sprintf("store(gesvd(repart(%s,%s),'values'),%s)",x@name,schema,d))
    iquery(sprintf("store(transpose(gesvd(repart(%s,%s),'right')),%s)",x@name,schema,v))
    ans = list(u=scidb(u,gc=TRUE),d=scidb(d,gc=TRUE),v=scidb(v,gc=TRUE))
    attr(ans$u,"sparse") = FALSE
    attr(ans$d,"sparse") = FALSE
    attr(ans$v,"sparse") = FALSE
    return(ans)
  }
  warning("Using the IRLBA truncated SVD algorithm")
  return(tsvd(x,nu))
}


# Miscellaneous functions
log_scidb = function(x, base=exp(1))
{
  w = scidb_types(x) == "double"
  if(!any(w)) stop("requires one double-precision valued attribute")
  if(class(x) %in% "scidb") attr = .get_attribute(x)
  else attr = x@attributes[which(w)[[1]]]
  new_attribute = sprintf("%s_log",attr)
  if(base==exp(1))
  {
    query = sprintf("apply(%s, %s, log(%s))",x@name, new_attribute, attr)
  } else if(base==10)
  {
    query = sprintf("apply(%s, %s, log10(%s))",x@name, new_attribute, attr)
  }
  else
  {
    query = sprintf("apply(%s, %s, log(%s)/log(%.15f))",x@name, new_attribute, attr, base)
  }
  .scidbeval(query,`eval`=FALSE)
}

# S4 method conforming to standard generic trig functions. See help for
# details about attribute selection and naming.
fn_scidb = function(x,fun,attr)
{
  if(missing(attr))
  {
    attr = x@attributes
  }
  new_attributes = make.unique_(x@attributes,attr)
  expr = paste(sprintf("%s, %s(%s)", new_attributes, fun, attr),collapse=",")
  query = sprintf("apply(%s, %s)",x@name, expr)
  query = sprintf("project(%s, %s)",query, paste(new_attributes,collapse=","))
  ren = paste(sprintf("%s,%s",new_attributes,attr),collapse=",")
  query = sprintf("attribute_rename(%s,%s)",query,ren)
  .scidbeval(query,`eval`=FALSE,gc=TRUE,depend=list(x),`data.frame`=(is.scidbdf(x)))
}

# S3 Method conforming to usual diff implementation. The `differences`
# argument is not supported here.
diff.scidb = function(x, lag=1, ...)
{
  y = lag(x,lag)
  n = make.unique_(c(x@attributes,y@attributes),"diff")
  z = merge(y,x,by=dimensions(x),all=FALSE)
  expr = paste(z@attributes,collapse=" - ")
  project(bind(z, n, expr), n)
}
