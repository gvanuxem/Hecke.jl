################################################################################
#
#  Locally free class group
#
################################################################################

@doc Markdown.doc"""
***
    locally_free_class_group(O::AlgAssAbsOrd)

> Given an order O in a semisimple algebra over QQ, this function returns the
> locally free class group of O.
"""
# Bley, Boltje "Computation of Locally Free Class Groups"
# If the left and right conductor of O in a maximal order coincide (which is the
# case if O is the integral group ring of a group algebra), the computation can
# be speeded up be setting cond = :left.
function locally_free_class_group(O::AlgAssAbsOrd, cond::Symbol = :center)
  A = algebra(O)
  Z, ZtoA = center(A)
  OA = maximal_order(A)
  Fl = conductor(O, OA, :left)
  if cond == :left
    F = Fl
    FinZ = _as_ideal_of_smaller_algebra(ZtoA, F)
  elseif cond == :center
    FinZ = _as_ideal_of_smaller_algebra(ZtoA, Fl)
    # Compute FinZ*OA but as an ideal of O
    bOA = basis(OA, copy = false)
    bFinZ = basis(FinZ, copy = false)
    basis_F = Vector{elem_type(O)}()
    t = one(A)
    for x in bOA
      for y in bFinZ
        yy = ZtoA(elem_in_algebra(y, copy = false))
        t = mul!(t, yy, elem_in_algebra(x, copy = false))
        push!(basis_F, O(t))
      end
    end
    F = ideal_from_z_gens(O, basis_F)
  elseif cond == :product
    Fr = conductor(O, OA, :right)
    F = Fr*Fl
    FinZ = _as_ideal_of_smaller_algebra(ZtoA, F)
  else
    error("Option :$(cond) for cond not implemented")
  end

  Adec = decompose(A)
  fields_and_maps = as_number_fields(Z)

  # Find the infinite places we need for the ray class group of FinZ
  inf_plc = Vector{Vector{InfPlc}}(undef, length(fields_and_maps))
  for i = 1:length(fields_and_maps)
    inf_plc[i] = Vector{InfPlc}()
  end
  for i = 1:length(Adec)
    B, BtoA = Adec[i]
    C, BtoC, CtoB = _as_algebra_over_center(B)
    K = base_ring(C)
    @assert K === fields_and_maps[i][1]

    places = real_places(K)
    for p in places
      if !issplit(C, p)
        push!(inf_plc[i], p)
      end
    end
  end

  R, mR = ray_class_group(FinZ, inf_plc)

  # Compute K_1(O/F) and the subgroup of R generated by nr(a)*OZ for a in k1 where
  # nr is the reduced norm and OZ the maximal order in Z
  k1 = K1_order_mod_conductor(O, F, FinZ)

  k1_as_subgroup = Vector{elem_type(R)}()
  for x in k1
    # It is possible that x is not invertible in A
    t = isinvertible(elem_in_algebra(x, copy = false))[1]
    while !t
      r = rand(F, 100)
      x += r
      t = isinvertible(elem_in_algebra(x, copy = false))[1]
    end
    s = _reduced_norms(elem_in_algebra(x, copy = false), mR)
    push!(k1_as_subgroup, s)
  end

  Cl, CltoR = quo(R, k1_as_subgroup)

  return snf(Cl)[1]
end

# Helper function for locally_free_class_group
# Computes the representative in the ray class group (domain(mR)) for the ideal
# nr(a)*O_Z, where nr is the reduced norm and O_Z the maximal order of the centre
# of A.
function _reduced_norms(a::AlgAssElem, mR::MapRayClassGroupAlg)
  A = parent(a)
  Adec = decompose(A)
  r = zero_matrix(FlintZZ, 1, 0)

  for i = 1:length(Adec)
    B, BtoA = Adec[i]
    C, BtoC, CtoB = _as_algebra_over_center(B)
    c = BtoC(BtoA\a)
    G, GtoIdl = mR.groups_in_number_fields[i]
    K = number_field(order(codomain(GtoIdl)))
    OK = maximal_order(K)
    @assert K === base_ring(C)
    nc = norm(c)
    I = OK(nc)*OK
    m = isqrt(dim(C))
    @assert m^2 == dim(C)
    b, J = ispower(I, m)
    @assert b
    g = GtoIdl\J
    r = hcat(r, g.coeff)
  end
  G = codomain(mR.into_product_of_groups)
  return mR.into_product_of_groups\G(r)
end

################################################################################
#
#  K1
#
################################################################################

# Computes generators for K_1(O/F) where F is the product of the left and right
# conductor of O in the maximal order.
# FinZ should be F intersected with the centre of algebra(O).
# See Bley, Boltje "Computation of Locally Free Class Groups"
function K1_order_mod_conductor(O::AlgAssAbsOrd, F::AlgAssAbsOrdIdl, FinZ::AlgAssAbsOrdIdl)
  A = algebra(O)
  Z, ZtoA = center(A)
  OZ = maximal_order(Z)
  OinZ = _as_order_of_smaller_algebra(ZtoA, O)

  facFinZ = factor(FinZ)
  prime_ideals = Dict{ideal_type(OinZ), Vector{ideal_type(OZ)}}()
  for (p, e) in facFinZ
    q = contract(p, OinZ)
    if haskey(prime_ideals, q)
      push!(prime_ideals[q], p)
    else
      prime_ideals[q] = [ p ]
    end
  end

  primary_ideals = Vector{Tuple{ideal_type(O), ideal_type(O)}}()
  for p in keys(prime_ideals)
    primes_above = prime_ideals[p]
    q = primes_above[1]^facFinZ[primes_above[1]]
    for i = 2:length(primes_above)
      q = q*primes_above[i]^facFinZ[primes_above[i]]
    end
    pO = _as_ideal_of_larger_algebra(ZtoA, p, O)
    qO = _as_ideal_of_larger_algebra(ZtoA, contract(q, OinZ), O)
    # The qO are primary ideals such that F = \prod (qO + F)
    push!(primary_ideals, (pO, qO))
  end

  moduli = Vector{ideal_type(O)}()
  for i = 1:length(primary_ideals)
    push!(moduli, primary_ideals[i][2] + F)
  end

  # Compute generators of K_1(O/q + F) for each q and put them together with the CRT
  elements_for_crt = Vector{Vector{elem_type(O)}}(undef, length(primary_ideals))
  for i = 1:length(primary_ideals)
    # We use the exact sequence
    # (1 + p + F)/(1 + q + F) -> K_1(O/q + F) -> K_1(O/p + F) -> 1
    (p, q) = primary_ideals[i]
    pF = p + F
    qF = moduli[i]
    char = basis_mat(p, copy = false)[1, 1]
    B, OtoB = AlgAss(O, pF, char)
    k1_B = K1(B)
    k1_O = [ OtoB\x for x in k1_B ]
    if pF != qF
      append!(k1_O, _1_plus_p_mod_1_plus_q_generators(pF, qF))
    end
    elements_for_crt[i] = k1_O
  end
  # Make the generators coprime to the other ideals
  if length(moduli) != 0 # maybe O is maximal
    k1 = make_coprime(elements_for_crt, moduli)
  else
    k1 = elem_type(O)[]
  end

  return k1
end

@doc Markdown.doc"""
***
     K1(A::AlgAss{T}) where { T <: Union{gfp_elem, Generic.ResF{fmpz}, fq, fq_nmod } }

> Given an algebra over a finite field, this function returns generators for K_1(A).
"""
function K1(A::AlgAss{T}) where { T <: Union{gfp_elem, Generic.ResF{fmpz}, fq, fq_nmod } }
  # We use the exact sequence 1 + J -> K_1(A) -> K_1(B/J) -> 1
  J = radical(A)
  onePlusJ = _1_plus_j(A, J)

  B, AtoB = quo(A, J)
  k1B = K1_semisimple(B)
  k1 = append!(onePlusJ, [ AtoB\x for x in k1B ])
  return k1
end

# Computes generators for K_1(A) with A semisimple as described in
# Bley, Boltje "Computation of Locally Free Class Groups", p. 84.
function K1_semisimple(A::AlgAss{T}) where { T <: Union{ gfp_elem, Generic.ResF{fmpz}, fq, fq_nmod } }

  Adec = decompose(A)
  k1 = Vector{elem_type(A)}()
  idems = [ BtoA(one(B)) for (B, BtoA) in Adec ]
  sum_idems = sum(idems)
  minus_idems = map(x -> -one(A)*x, idems)
  for i = 1:length(Adec)
    B, BtoA = Adec[i]
    C, BtoC, CtoB = _as_algebra_over_center(B)
    F = base_ring(C)
    # Consider C as a matrix algebra over F. Then the matrices with a one somewhere
    # on the diagonal are given by primitive idempotents (see also _as_matrix_algebra).
    prim_idems = _primitive_idempotents(C)
    a = _primitive_element(F)
    # aC is the identity matrix with a at position (1, 1)
    aC = a*prim_idems[1]
    if dim(C) > 1
      for j = 2:length(prim_idems)
        aC = add!(aC, aC, prim_idems[j])
      end
    end
    aA = BtoA(CtoB(aC))
    # In the other components aA should be 1 (this is not mentioned in the Bley/Boltje-Paper)
    aA = add!(aA, aA, sum_idems)
    aA = add!(aA, aA, minus_idems[i])
    push!(k1, aA)
  end
  return k1
end

# Computes generators for 1 + J where J is the Jacobson Radical of A
function _1_plus_j(A::AlgAss{T}, jacobson_radical::AbsAlgAssIdl...) where { T <: Union{ gfp_elem, Generic.ResF{fmpz}, fq_nmod, fq } }
  F = base_ring(A)

  if length(jacobson_radical) == 1
    J = jacobson_radical[1]
  else
    J = radical(A)
  end

  onePlusJ = Vector{elem_type(A)}()

  if iszero(J)
    return onePlusJ
  end

  # We use the filtration 1 + J \supseteq 1 + J^2 \subseteq ... \subseteq 1
  oneA = one(A)
  while !iszero(J)
    J2 = J^2
    Q, AtoQ = quo(J, J2)
    for i = 1:dim(Q)
      push!(onePlusJ, one(A) + AtoQ\Q[i])
    end
    J = J2
  end
  return onePlusJ
end
