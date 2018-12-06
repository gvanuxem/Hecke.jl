@doc Markdown.doc"""
    compact_presentation(a::FacElem{nf_elem, AnticNumberField}, n::Int = 2; decom, arb_prec = 100, short_prec = 1000) -> FacElem
> Computes a presentation $a = \prod a_i^{n_i}$ where all the exponents $n_i$ are powers of $n$
> and, the elements $a$ are "small", generically, they have a norm bounded by $d^{n/2}$ where
> $d$ is the discriminant of the maximal order.
> As the algorithm needs the factorisation of the principal ideal generated by $a$, it can
> be passed in in \code{decom}.
"""
function compact_presentation(a::FacElem{nf_elem, AnticNumberField}, nn::Int = 2; decom=false, arb_prec = 100, short_prec = 128)

  n = fmpz(nn)

  K = base_ring(a)
  ZK = maximal_order(K)
  if typeof(decom) == Bool
    de::Dict{NfOrdIdl, fmpz} = factor_coprime(a, IdealSet(ZK))
  else
    de = Dict((p, v) for (p, v) = decom)
  end
  de_inv =Dict{NfOrdIdl, NfOrdFracIdl}()

  be = FacElem(K(1))

  @hassert :CompactPresentation 1 length(decom) == 0 && isone(abs(factored_norm(a))) == 1 ||
                                  abs(factored_norm(a)) == factored_norm(FacElem(decom))

  v = conjugates_arb_log_normalise(a, arb_prec)
  _v = maximum(abs, values(de))+1

  #Step 1: reduce the ideal in a p-power way...

  A = ideal(ZK, 1)
  for _k = floor(Int, log(Int(n), Int(_v))):-1:0
    B = Dict((p, div(v, Int(n^_k)) % Int(n)) for (p, v) = de)
    if haskey(B, A)
      B[A] = B[A] + n
    else
      B[A] = n
    end
    A, alpha = reduce_ideal2(FacElem(B))
    be *= alpha^(-(n^_k))
    v -= Ref(n^_k) .* conjugates_arb_log_normalise(alpha, arb_prec)
  end
  if length(be.fac) > 1
    delete!(be.fac, K(1))
  end

  #Step 2: now reduce the infinite valuation

  r1, r2 = signature(K)
 
  m = maximum(abs, values(de))
  m = max(m, 1)
  mm = abs_upper_bound(log(1+maximum(abs, v))//log(n), fmpz)
  k = max(ceil(Int, log(m)/log(n)), Int(mm))

  de = Dict(A => fmpz(1))
  delete!(de, ideal(ZK, 1))
  B=0
  
  @hassert :CompactPresentation 1 length(de) == 0 && isone(abs(factored_norm(a*be))) == 1 ||
                                  abs(factored_norm(a*be)) == factored_norm(FacElem(de))

  @hassert :CompactPresentation 2 length(de) != 0 || isone(ideal(ZK, a*be)) 
  @hassert :CompactPresentation 2 length(de) == 0 || ideal(ZK, a*be) == FacElem(de)

  while k>=1
    @vprint :CompactPresentation 1 "k now: $k\n"
    D = Dict((p, div(fmpz(v), n^k)) for (p, v) = de if v >= n^k)
    if length(D) == 0
      A = FacElem(Dict(ideal(ZK, 1) => 1))
    else
      A = FacElem(D)
    end
    vv = [x//n^k for x = v]
    vvv = fmpz[]
    for i=1:r1
      while !radiuslttwopower(vv[i], -5)
        arb_prec *= 2
        v = conjugates_arb_log_normalise(a*be, arb_prec)
        vv = [x//n^k for x = v]
      end
      push!(vvv, round(fmpz, vv[i]//log(2)))
    end
    for i=r1+1:r1+r2
      while !radiuslttwopower(vv[i], -5)
        arb_prec *= 2
        v = conjugates_arb_log_normalise(a*be, arb_prec)
        vv = [x//n^k for x = v]
      end
      local r = round(fmpz, vv[i]//log(2)//2)
      push!(vvv, r)
      push!(vvv, r)
    end
    @assert abs(sum(vvv)) <= degree(K)
    @vtime :CompactPresentation 1 id = inv(simplify(evaluate(A, coprime = true)))
    @vtime :CompactPresentation 1 b = short_elem(id, matrix(FlintZZ, 1, length(vvv), vvv), prec = short_prec) # the precision needs to be done properly...
    @assert abs(norm(b)//norm(id)) <= abs(discriminant(ZK)) # the trivial case
    B = simplify(ideal(ZK, b))
    @assert B.num.is_principal == 1  
    @assert isone(B.num) || B.num.gens_normal > 1
    assure_2_normal(B.num)

    for p = keys(de)
      assure_2_normal(p)
      local _v = valuation(b, p)
      @hassert :CompactPresentation 1 valuation(B, p) == _v
      de[p] += n^k*_v
      if haskey(de_inv, p)
        pi = de_inv[p]
      else
        pi = inv(p)
        de_inv[p] = pi
      end
      B *= pi^_v
      B = simplify(B)
      @hassert :CompactPresentation 1 valuation(B, p) == 0
    end
    @assert !haskey(de, ideal(ZK, 1))
    @assert norm(B) <= abs(discriminant(ZK))

    for (p, _v) = factor(B)
      if haskey(de, p)
        de[p] += _v*n^k
        continue
      end
      @assert !isone(p)
      insert_prime_into_coprime(de, p, _v*n^k)
    end
    v_b = conjugates_arb_log_normalise(b, arb_prec)
    @v_do :CompactPresentation 2 @show old_n = sum(x^2 for x = v)
    v += Ref(n^k) .* v_b
    @v_do :CompactPresentation 2 @show new_n = sum(x^2 for x = v)
    @v_do :CompactPresentation 2 @show old_n / new_n 

    be  *= FacElem(b)^(n^k)
    @hassert :CompactPresentation 1 length(de) == 0 && isone(abs(factored_norm(a*be))) == 1 ||
                                    abs(factored_norm(a*be)) == factored_norm(FacElem(de))
    @hassert :CompactPresentation 2 length(de) != 0 || isone(ideal(ZK, a*be)) 
    @hassert :CompactPresentation 2 length(de) == 0 || ideal(ZK, a*be) == FacElem(de)
    k -= 1
  end
  if length(de) == 0
    de[ideal(ZK, 1)] = 1
  end
  @hassert :CompactPresentation 2 length(de) != 0 || isone(ideal(ZK, a*be)) 
  @hassert :CompactPresentation 2 length(de) == 0 || ideal(ZK, a*be) == FacElem(de)
  @hassert :CompactPresentation 1 length(de) == 0 && isone(abs(factored_norm(a*be))) == 1 ||
                                    factored_norm(ideal(ZK, a*be)) == abs(factored_norm(FacElem(de)))
  @vprint :CompactPresentation 1 "Final eval...\n"
  @vtime :CompactPresentation 1 A = evaluate(FacElem(de), coprime = true)
  @vtime :CompactPresentation 1 b = evaluate_mod(a*be, A)
  return inv(be)*b
end

function insert_prime_into_coprime(de::Dict{NfOrdIdl, fmpz}, p::NfOrdIdl, e::fmpz)
  @assert !isone(p)
  P = p.gen_one
  for k=keys(de)
    if k.gen_one % P == 0
      if k.splitting_type[2] == 0
        #k is not known to be prime, so p could divide...
        v1 = valuation(k, p)
        if v1 == 0
          continue
        end
        #since it divides k it cannot divide any other (coprime!)
        p2 = simplify(k*inv(p)^v1).num
        if !isone(p2)
          de[p2] = de[k]
        end
        de[p] = de[k]*v1+e
        delete!(de, k)
        return
      else
        #both are know to be prime, and p is new to the dict.
        @assert p != k
      end
    end
  end
  de[p] = e
end

#TODO: use the log as a stopping condition as well
@doc Markdown.doc"""
    evaluate_mod(a::FacElem{nf_elem, AnticNumberField}, B::NfOrdFracIdl) -> nf_elem
> Evaluates $a$ using CRT and small primes. Assumes that the ideal generated by $a$ is in fact $B$.
> Useful in cases where $a$ has huge exponents, but the evaluated element is actually "small".
"""
function evaluate_mod(a::FacElem{nf_elem, AnticNumberField}, B::NfOrdFracIdl)
  p = fmpz(next_prime(p_start))
  K = base_ring(a)
  ZK = maximal_order(K)
  dB = denominator(B)*index(ZK)

  @hassert :CompactPresentation 1 factored_norm(B) == abs(factored_norm(a))
  @hassert :CompactPresentation 2 B == ideal(order(B), a)

  @assert order(B) == ZK
  pp = fmpz(1)
  re = K(0)
  while (true)
    me = modular_init(K, p)
    mp = Ref(dB) .* modular_proj(a, me)
    m = modular_lift(mp, me)
    if pp == 1
      re = m
      pp = p
    else
      p2 = pp*p
      last = re
      re = induce_inner_crt(re, m, pp*invmod(pp, p), p2, div(p2, 2))
      if re == last
        return re//dB
      end
      pp = p2
    end
    @hassert :CompactPresentation 1 nbits(pp) < 10000
    p = next_prime(p)
  end
end

function Hecke.ispower(a::FacElem{nf_elem, AnticNumberField}, n::Int; decom = false)
  if n == 1
    return true, a
  end
  @assert n > 1
  if typeof(decom) == Bool
    ZK = maximal_order(base_ring(a))
    de::Dict{NfOrdIdl, fmpz} = factor_coprime(a, IdealSet(ZK))
  else
    de = Dict((p, v) for (p, v) = decom)
  end
  c = Hecke.compact_presentation(a, n, decom = de)
  b = base_ring(c)(1)
  d = FacElem(b)
  for (k,v) = c.fac
    q, r = divrem(v, n)
    if r < 0
      r += n
      q -= 1
      @assert r > 0
      @assert n*q+r == v
    end
    d *= FacElem(Dict(k => q))
    b *= k^r
  end
  @hassert :CompactPresentation 2 evaluate(d^n*b *inv(a))== 1
  fl, x = ispower(b, n)
  if fl
    return fl, d*x
  else
    return fl, d
  end
end

