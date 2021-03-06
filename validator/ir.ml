open Sexplib.Conv
open Core.Std

module Sexp = Core.Std.Sexp

type bop = Eq | Le | Lt | Ge | Gt
         | Add | Sub | Mul
         | And | Bit_and with sexp


type ttype = | Ptr of ttype
             | Sint32
             | Sint8
             | Uint64
             | Uint32
             | Uint16
             | Uint8
             | Void
             | Str of string * (string * ttype) list
             | Ctm of string
             | Fptr of string
             | Boolean
             | Sunknown
             | Uunknown
             | Unknown
with sexp

type term_util = Ptr_placeholder of int64
with sexp

type term = Bop of bop*tterm*tterm
          | Apply of string*tterm list
          | Id of string
          | Struct of string*var_spec list
          | Int of int
          | Bool of bool
          | Not of tterm
          | Str_idx of tterm*string
          | Deref of tterm
          | Addr of tterm
          | Fptr of string
          | Cast of ttype*tterm
          | Zeroptr
          | Undef
          | Utility of term_util
and tterm = {v:term; t:ttype}
and var_spec = {name: string; value:tterm}
with sexp

type eq_condition = {lhs: tterm; rhs: tterm} with sexp

let rec ttype_to_str = function
  | Ptr c_type -> ttype_to_str c_type ^ "*"
  | Sint32 -> "int" | Sint8 -> "char"
  | Uint64 -> "uint64_t"| Uint32 -> "uint32_t"
  | Uint16 -> "uint16_t" | Uint8 -> "uint8_t"
  | Void -> "void" | Str (name, _) -> "struct " ^ name
  | Ctm name -> name | Fptr name -> name ^ "*" | Boolean -> "bool"
  | Unknown -> "???"
  | Sunknown -> "s??" | Uunknown -> "u??"

let is_void = function | Void -> true | _ -> false

let get_pointee = function | Ptr t -> t
                           | x -> failwith ((ttype_to_str x) ^
                                            " is not a plain pointer")

type fun_call_context = {
  extra_pre_conditions: eq_condition list;
  pre_lemmas:string list;
  application:term;
  post_lemmas:string list;
  ret_name:string option;
  ret_type:ttype;
  call_id:int;
} with sexp

type hist_call_result = {
  args_post_conditions:eq_condition list;
  ret_val:tterm;
} with sexp

type tip_result = {
  args_post_conditions:eq_condition list;
  ret_val:tterm;
  post_statements:tterm list;
} with sexp

type hist_call = {
  context:fun_call_context;
  result:hist_call_result;
} with sexp

type tip_call = {context:fun_call_context;
                 results:tip_result list} with sexp

type ir = {
  preamble:string;
  free_vars:var_spec String.Map.t; (* TODO: var_spec -> typed_var *)
  arguments:var_spec list; (*FIXME: holds also extra ptrs*)
  tmps:var_spec String.Map.t;
  cmplxs:var_spec String.Map.t;
  context_assumptions:tterm list;
  hist_calls:hist_call list;
  tip_call:tip_call;
  export_point:string;
  finishing:bool;
  complete_event_loop_iteration:bool;
  semantic_checks:string;
} with sexp

let strip_outside_parens str =
  if (String.is_prefix str ~prefix:"(") &&
     (String.is_suffix str ~suffix:")") then
    String.chop_prefix_exn (String.chop_suffix_exn str ~suffix:")")
      ~prefix:"("
  else str

let render_bop = function
  | Eq -> "=="
  | Le -> "<="
  | Lt -> "<"
  | Ge -> ">="
  | Gt -> ">"
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | And -> "&&"
  | Bit_and -> "&"

let rec simplify_term term =
  match term with
  | Apply (fname,args) -> Apply (fname, (List.map args ~f:(fun {v;t}->
      {v=simplify_term v;t})))
  | Deref {t=_;v=Addr x} -> simplify_term x.v
  | Str_idx (x,fname) -> Str_idx ({v=simplify_term x.v;t=x.t}, fname)
  | _ -> term

let render_utility = function
  | Ptr_placeholder addr -> "?placeholder addr:" ^ (Int64.to_string addr)

let int_type_postfix = function
  | Uint64 -> "ULL"
  | _ -> ""

let rec render_tterm (t:tterm) =
  match t.v with  (*strip parens: account for weird VeriFast parser*)
  | Bop (op, lhs, rhs) -> "(" ^ (strip_outside_parens (render_tterm lhs)) ^
                          " " ^ (render_bop op) ^ " " ^
                          (render_tterm rhs) ^ ")"
  | Apply (fname,args) ->
    let arg_strings = List.map args ~f:render_tterm in
    fname ^ "(" ^ (String.concat ~sep:", " arg_strings) ^ ")"
  | Id name -> name;
  | Struct (_,fields) ->
    "{" ^ (String.concat ~sep:", "
             (List.map fields ~f:(fun {name;value} ->
                  "." ^ name ^ " = " ^ (render_tterm value)))) ^
    "}"
  | Int 0 -> if (t.t = Boolean) then "false" else ("0"^ (int_type_postfix t.t))
  | Int 1 -> if (t.t = Boolean) then "true" else ("1"^ (int_type_postfix t.t))
  | Int i -> string_of_int i ^ (int_type_postfix t.t)
  | Bool b -> string_of_bool b
  | Not t -> "!(" ^ (render_tterm t) ^ ")"
  | Str_idx ({v=Id x;t=_}, field_name) -> x ^ "." ^ field_name
  | Str_idx ({v=Str_idx ({v=Id x;t=_}, fname1);t=_}, fname2) ->
    x ^ "." ^ fname1 ^ "." ^ fname2
  | Str_idx ({v=Str_idx ({v=Str_idx ({v=Id x;t=_}, fname1);t=_},
                         fname2);t=_},
             fname3) ->
    x ^ "." ^ fname1 ^ "." ^ fname2 ^ "." ^ fname3
  | Str_idx ({v=Deref {v=Id x;t=_};t=_},field_name) -> x ^ "->" ^ field_name
  | Str_idx ({v=Deref x;t},field_name) -> "(" ^ (render_tterm x) ^ ")->" ^ field_name
  | Str_idx (t,field_name) -> "(" ^ (render_tterm t) ^ ")." ^ field_name
  | Deref t -> "*(" ^ (render_tterm t) ^ ")"
  | Fptr f -> f
  | Addr t -> "&(" ^ (render_tterm t) ^ ")"
  | Cast (t,v) -> "(" ^ ttype_to_str t ^ ")" ^ (render_tterm v)
  | Zeroptr -> "0"(*"NULL"*)
  | Undef -> "???"
  | Utility util -> render_utility util
and render_term t = render_tterm {v=t;t=Unknown} (*TODO: reformulate this coupled definition*)

let term_utility_eq a b =
  match a, b with
  | Ptr_placeholder x, Ptr_placeholder y -> (x = y)

let rec term_eq a b =
  match a,b with
  | Bop (opa,lhsa,rhsa), Bop (opb,lhsb,rhsb) ->
    opa = opb && (term_eq lhsa.v lhsb.v) && (term_eq rhsa.v rhsb.v)
  | Apply (fa,argsa), Apply (fb, argsb) ->
    (String.equal fa fb) && ((List.length argsa) = (List.length argsb)) &&
    (List.for_all2_exn argsa argsb ~f:(fun arga argb -> term_eq arga.v argb.v))
  | Id a, Id b -> String.equal a b
  | Struct (sna,fdsa), Struct (snb,fdsb) ->
    (String.equal sna snb) && ((List.length fdsa) = (List.length fdsb)) &&
    (List.for_all2_exn fdsa fdsb ~f:(fun {name=fnamea;value=fvala}
                                      {name=fnameb;value=fvalb} ->
         (String.equal fnamea fnameb) &&
         term_eq fvala.v fvalb.v))
  | Int ia, Int ib -> ia = ib
  | Bool ba, Bool bb -> ba = bb
  | Not tta, Not ttb -> term_eq tta.v ttb.v
  | Str_idx (tta,fda), Str_idx (ttb,fdb) -> term_eq tta.v ttb.v && String.equal fda fdb
  | Deref tta, Deref ttb -> term_eq tta.v ttb.v
  | Fptr fa, Fptr fb -> String.equal fa fb
  | Addr tta, Addr ttb -> term_eq tta.v ttb.v
  | Cast (ctypea,terma), Cast (ctypeb,termb) -> (ctypea = ctypeb) && (term_eq terma.v termb.v)
  | Undef, Undef -> true
  | Utility ua, Utility ub -> term_utility_eq ua ub
  | _, _ -> false

let rec call_recursively_on_tterm (f:tterm -> tterm option) tterm =
  let recursion_in_utility f = function
    | Ptr_placeholder x -> Ptr_placeholder x
  in
  let tterm =
    {v= begin
        match tterm.v with
        | Bop (op,lhs,rhs) ->
          Bop (op, call_recursively_on_tterm f lhs, call_recursively_on_tterm f rhs)
        | Apply (fname,args) ->
          Apply (fname, List.map args ~f:(call_recursively_on_tterm f))
        | Id x -> Id x
        | Struct (name,fds) ->
          Struct (name,List.map fds ~f:(fun field ->
              {field with value = call_recursively_on_tterm f field.value}))
        | Int i -> Int i
        | Bool b -> Bool b
        | Not x -> Not (call_recursively_on_tterm f x)
        | Str_idx (tt,fname) -> Str_idx (call_recursively_on_tterm f tt,fname)
        | Deref tt -> Deref (call_recursively_on_tterm f tt)
        | Fptr fname -> Fptr fname
        | Addr tt -> Addr (call_recursively_on_tterm f tt)
        | Cast (ctype,tt) -> Cast (ctype,call_recursively_on_tterm f tt)
        | Undef -> Undef
        | Zeroptr -> Zeroptr
        | Utility u -> Utility (recursion_in_utility f u)
      end;
     t=tterm.t} in
  match f tterm with
  | Some tt -> tt
  | None -> tterm

let call_recursively_on_term (f:term -> term option) tterm =
  call_recursively_on_tterm (fun {v;t} -> match f v with
      | Some v -> Some {v;t}
      | None -> None) tterm

let rec replace_term_in_term old_t new_t term =
  let replace_in_utility old_t new_t = function
    | Ptr_placeholder x -> Ptr_placeholder x
  in
  if term_eq term old_t then new_t else
    match term with
    | Bop (opa,lhs,rhs) ->
      Bop (opa,replace_term_in_tterm old_t new_t lhs,
           replace_term_in_tterm old_t new_t rhs)
    | Apply (f,args) -> Apply (f,replace_term_in_tterms old_t new_t args)
    | Id x -> Id x
    | Struct (name,fields) ->
      Struct (name, List.map fields ~f:(fun field ->
          {field with value = replace_term_in_tterm old_t new_t field.value}))
    | Int _ -> term
    | Bool _ -> term
    | Not t -> Not (replace_term_in_tterm old_t new_t t)
    | Str_idx (term,field) ->
      Str_idx (replace_term_in_tterm old_t new_t term,field)
    | Deref term -> Deref (replace_term_in_tterm old_t new_t term)
    | Fptr _ -> term
    | Addr tterm -> Addr (replace_term_in_tterm old_t new_t tterm)
    | Cast (ctype,tterm) ->
      Cast (ctype,replace_term_in_tterm old_t new_t tterm)
    | Undef -> Undef
    | Zeroptr -> Zeroptr
    | Utility util -> Utility (replace_in_utility old_t new_t util)
and replace_term_in_tterm old_t new_t tterm =
  {tterm with v=replace_term_in_term old_t new_t tterm.v}
and replace_term_in_tterms old_t new_t tterm_list =
  List.map tterm_list ~f:(replace_term_in_tterm old_t new_t)


let rec collect_nodes f tterm =
  let collect_on_utility f = function
    | Ptr_placeholder _ -> []
  in
  match f tterm with
  | Some x -> [x]
  | None ->
    match tterm.v with
    | Bop (_,lhs,rhs) -> (collect_nodes f lhs) @ (collect_nodes f rhs)
    | Apply (_,args) -> List.join (List.map args ~f:(collect_nodes f))
    | Id _ -> []
    | Struct (_,fields) ->
      List.join (List.map fields ~f:(fun {name=_;value} ->
          collect_nodes f value))
    | Int _ -> []
    | Bool _ -> []
    | Not x -> collect_nodes f x
    | Str_idx (str,_) -> collect_nodes f str
    | Deref ptr -> collect_nodes f ptr
    | Fptr _ -> []
    | Addr v -> collect_nodes f v
    | Cast (_,v) -> collect_nodes f v
    | Undef -> []
    | Zeroptr -> []
    | Utility u -> collect_on_utility f u

let rec term_contains_term super sub =
  let utility_contains sub = function
    | Ptr_placeholder _ -> false
  in
  if term_eq super sub then true else
    match super with
    | Bop (_,lhs,rhs) ->
      tterm_contains_term lhs sub || tterm_contains_term rhs sub
    | Apply (_,args) -> tterms_contain_term args sub
    | Id _ -> false
    | Struct (_,fields) ->
      List.exists fields ~f:(fun field ->
        tterm_contains_term field.value sub)
    | Int _ -> false
    | Bool _ -> false
    | Not t -> tterm_contains_term t sub
    | Str_idx (term,_) ->
      tterm_contains_term term sub
    | Deref term -> tterm_contains_term term sub
    | Fptr _ -> false
    | Addr tterm -> tterm_contains_term tterm sub
    | Cast (_,tterm) ->
      tterm_contains_term tterm sub
    | Undef -> false
    | Zeroptr -> false
    | Utility u -> utility_contains sub u
and tterm_contains_term super sub =
  term_contains_term super.v sub
and tterms_contain_term supers sub =
  List.exists supers ~f:(fun sup -> tterm_contains_term sup sub)

let rec is_const term =
  let is_utility_const = function
    | Ptr_placeholder _ -> false
  in
  match term with
  | Bop (_,lhs,rhs) -> (is_constt lhs) && (is_constt rhs)
  | Apply (_,args) -> List.for_all args ~f:is_constt
  | Id _ -> false
  | Struct (_,fields) -> List.for_all fields
                           ~f:(fun field -> is_constt field.value)
  | Int _ -> true
  | Bool _ -> true
  | Not t -> is_constt t
  | Str_idx (tterm,_) -> is_constt tterm
  | Deref tterm -> is_constt tterm
  | Fptr _ -> true
  | Addr tterm -> is_constt tterm
  | Cast (_,tterm) -> is_constt tterm
  | Undef -> true
  | Zeroptr -> true
  | Utility u -> is_utility_const u
and is_constt tterm = is_const tterm.v
