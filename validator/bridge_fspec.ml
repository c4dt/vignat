
open Core.Std
open Fspec_api
open Ir

type map_key = Int | Ext

let last_index_gotten = ref ""
let last_index_key = ref Int
let last_indexing_succ_ret_var = ref ""
let last_device_id = ref ""

let last_time_for_index_alloc = ref ""
let the_array_lcc_is_local = ref true

let capture_chain ch_name ptr_num args tmp =
  "//@ assert double_chainp(?" ^ (tmp ch_name) ^ ", " ^
  (List.nth_exn args ptr_num) ^ ");\n"

let map_struct = Ir.Str ("Map", [])
let vector_struct = Ir.Str ( "Vector", [] )
let dchain_struct = Ir.Str ( "DoubleChain", [] )
let ether_addr_struct = Ir.Str ( "ether_addr", [])
let static_key_struct = Ir.Str ( "StaticKey", ["addr", ether_addr_struct;
                                               "device", Uint8] )
let dynamic_entry_struct = Ir.Str ( "DynamicEntry", ["addr", ether_addr_struct;
                                                     "device", Uint8] )
let ether_hdr_struct = Ir.Str ("ether_hdr", ["d_addr", ether_addr_struct;
                                             "s_addr", ether_addr_struct;
                                             "ether_type", Uint16;])
let user_buf_struct = Ir.Str ("user_buf", ["ether", ether_hdr_struct;])
let rte_mbuf_struct = Ir.Str ( "rte_mbuf",
                               ["buf_addr", Ptr user_buf_struct;
                                "buf_physaddr", Uint64;
                                "buf_len", Uint16;
                                "data_off", Uint16;
                                "refcnt", Uint16;
                                "nb_segs", Uint8;
                                "port", Uint8;
                                "ol_flags", Uint64;
                                "packet_type", Uint32;
                                "pkt_len", Uint32;
                                "data_len", Uint16;
                                "vlan_tci", Uint16;
                                "hash", Uint32;
                                "seqn", Uint32;
                                "vlan_tci_outer", Uint16;
                                "udata64", Uint64;
                                "pool", Ptr Void;
                                "next", Ptr Void;
                                "tx_offload", Uint64;
                                "priv_size", Uint16;
                                "timesync", Uint16] )

let copy_user_buf var_name ptr =
  deep_copy
    {Ir.name=var_name;
     Ir.value={v=Deref {v=Ir.Id ("((" ^ ptr ^ ")->buf_addr)");
                        t=Ptr user_buf_struct};
               t=user_buf_struct}}

let fun_types =
  String.Map.of_alist_exn
    ["current_time", {ret_type = Uint32;
                      arg_types = [];
                      extra_ptr_types = [];
                      lemmas_before = [];
                      lemmas_after = [
                        (fun params ->
                           "uint32_t now = " ^ (params.ret_name) ^ ";\n")];};
     "dchain_allocate", {ret_type = Sint32;
                         arg_types = [Sint32; Ptr (Ptr dchain_struct)];
                         extra_ptr_types = [];
                         lemmas_before = [];
                         lemmas_after = [
                           on_rez_nonzero
                               "empty_dmap_dchain_coherent\
                                <int_k,ext_k,flw>(65536);";
                           tx_l "index_range_of_empty(65536, 0);";];};
     "dchain_allocate_new_index", {ret_type = Sint32;
                                   arg_types = [Ptr dchain_struct; Ptr Sint32; Uint32;];
                                   extra_ptr_types = [];
                                   lemmas_before = [
                                     capture_chain "cur_ch" 0;
                                   ];
                                   lemmas_after = [
                                     on_rez_nz
                                       (fun params ->
                                          "{\n allocate_preserves_index_range(" ^
                                          (params.tmp_gen "cur_ch") ^
                                          ", *" ^
                                          (List.nth_exn params.args 1) ^ ", " ^
                                          (List.nth_exn params.args 2) ^ ");\n}");
                                     (fun params ->
                                        "//@ allocate_keeps_high_bounded(" ^
                                        (params.tmp_gen "cur_ch") ^
                                        ", *" ^ (List.nth_exn params.args 1) ^
                                        ", " ^ (List.nth_exn params.args 2) ^
                                        ");\n");
                                     (fun params ->
                                        last_time_for_index_alloc :=
                                          (List.nth_exn params.args 2);
                                        "");
                                     (fun params ->
                                        "int the_index_allocated = *" ^
                                        (List.nth_exn params.args 1) ^ ";\n");
                                   ];};
     "dchain_rejuvenate_index", {ret_type = Sint32;
                                 arg_types = [Ptr dchain_struct; Sint32; Uint32;];
                                 extra_ptr_types = [];
                                 lemmas_before = [
                                   capture_chain "cur_ch" 0;
                                   (fun args tmp ->
                                      "/*@ {\n\
                                       assert dmap_dchain_coherent(?cur_map, " ^
                                      (tmp "cur_ch") ^
                                      ");\n coherent_same_cap(cur_map, " ^
                                      (tmp "cur_ch") ^ ");\n" ^
                                      "rejuvenate_flow_abstract(cur_map," ^
                                      (tmp "cur_ch") ^ ", " ^
                                      "dmap_get_val_fp(cur_map, " ^
                                      (List.nth_exn args 1) ^ ")," ^
                                      (List.nth_exn args 1) ^ ", " ^
                                      (List.nth_exn args 2) ^ ");\n" ^
                                      "} @*/");
                                   (fun args tmp ->
                                      "//@ rejuvenate_keeps_high_bounded(" ^
                                      (tmp "cur_ch") ^
                                      ", " ^ (List.nth_exn args 1) ^
                                      ", " ^ (List.nth_exn args 2) ^
                                      ");\n");];
                                 lemmas_after = [
                                   (fun params ->
                                      "/*@ if (" ^ params.ret_name ^
                                      " != 0) { \n" ^
                                      "assert dmap_dchain_coherent(?cur_map,?ch);\n" ^
                                      "rejuvenate_preserves_coherent(cur_map, ch, " ^
                                      (List.nth_exn params.args 1) ^ ", "
                                      ^ (List.nth_exn params.args 2) ^ ");\n\
                                       rejuvenate_preserves_index_range(ch," ^
                                      (List.nth_exn params.args 1) ^ ", " ^
                                      (List.nth_exn params.args 2) ^ ");\n}@*/");
                                   (fun params ->
                                      "int the_index_rejuvenated = " ^
                                      (List.nth_exn params.args 1) ^ ";\n");
                                 ];};
     "expire_items_single_map", {ret_type = Sint32;
                                 arg_types = [Ptr dchain_struct;
                                              Ptr vector_struct;
                                              Ptr map_struct;
                                              Fptr "entry_extract_key";
                                              Fptr "entry_pack_key";
                                             Uint32];
                                 extra_ptr_types = [];
                                 lemmas_before = [];
                                 lemmas_after = [];};
     "map_allocate", {ret_type = Sint32;
                      arg_types = [Fptr "map_keys_equality";
                                   Fptr "map_key_hash";
                                   Sint32;
                                   Ptr (Ptr map_struct)];
                      extra_ptr_types = [];
                      lemmas_before = [
                        tx_bl "produce_function_pointer_chunk \
                               map_keys_equality<stat_keyi>(static_key_eq)\
                               (static_keyp)(a, b) \
                               {\
                               call();\
                               }";
                        tx_bl "produce_function_pointer_chunk \
                               map_key_hash<stat_keyi>(static_key_hash)\
                               (static_keyp, st_key_hash)(a) \
                               {\
                               call();\
                               }";];
                      lemmas_after = [];};
     "map_get", {ret_type = Sint32;
                 arg_types = [Ptr map_struct;
                              Ptr Void;
                              Ptr Sint32];
                 extra_ptr_types = [];
                 lemmas_before = [];
                 lemmas_after = [];};
     "map_put", {ret_type = Void;
                 arg_types = [Ptr map_struct;
                              Ptr Void;
                              Sint32];
                 extra_ptr_types = [];
                 lemmas_before = [];
                 lemmas_after = [];};
     "received_packet", {ret_type = Void;
                         arg_types = [Ir.Uint8; Ptr rte_mbuf_struct;];
                         extra_ptr_types = ["user_buf_addr", user_buf_struct];
                         lemmas_before = [];
                         lemmas_after = [(fun _ -> "a_packet_received = true;\n");
                                         (fun params ->
                                            let recv_pkt =
                                              (List.nth_exn params.args 1)
                                            in
                                            (copy_user_buf "the_received_packet"
                                               recv_pkt) ^ "\n" ^
                                            "received_on_port = (" ^
                                            recv_pkt ^ ")->port;\n" ^
                                            "received_packet_type = (" ^
                                            recv_pkt ^ ")->packet_type;");
                                           ];};
     "rte_pktmbuf_free", {ret_type = Void;
                          arg_types = [Ptr rte_mbuf_struct;];
                          extra_ptr_types = [];
                          lemmas_before = [];
                          lemmas_after = [];};
     "send_single_packet", {ret_type = Ir.Sint32;
                            arg_types = [Ptr rte_mbuf_struct; Ir.Uint8];
                            extra_ptr_types = ["user_buf_addr", user_buf_struct];
                            lemmas_before = [];
                            lemmas_after = [(fun _ -> "a_packet_sent = true;\n");
                                            (fun params ->
                                               let sent_pkt =
                                                 (List.nth_exn params.args 0)
                                               in
                                               (copy_user_buf "sent_packet"
                                                  sent_pkt) ^ "\n" ^
                                               "sent_on_port = " ^
                                               (List.nth_exn params.args 1) ^
                                               ";\n" ^
                                               "sent_packet_type = (" ^
                                               sent_pkt ^ ")->packet_type;");];};
     "start_time", {ret_type = Uint32;
                    arg_types = [];
                    extra_ptr_types = [];
                    lemmas_before = [];
                    lemmas_after = [];};
     "vector_allocate", {ret_type = Sint32;
                         arg_types = [Sint32;
                                      Sint32;
                                      Fptr "vector_init_elem";
                                      Ptr (Ptr vector_struct)];
                         extra_ptr_types = [];
                         lemmas_before = [
                           (fun args _ ->
                              "/*@ //TODO: this hack should be \
                               converted to a system \n\
                               assume(sizeof(struct DynamicEntry) == " ^
                              (List.nth_exn args 0) ^ ");\n@*/\n");
                           tx_bl "produce_function_pointer_chunk \
                                  vector_init_elem<dynenti>(init_nothing)\
                                  (dynamic_entryp, sizeof(struct DynamicEntry))(a) \
                                  {\
                                  call();\
                                  }";
                         ];
                         lemmas_after = [];};
     "vector_borrow", {ret_type = Ptr Void;
                       arg_types = [Ptr vector_struct;
                                    Sint32];
                       extra_ptr_types = [];
                       lemmas_before = [];
                       lemmas_after = [];};
     "vector_return", {ret_type = Void;
                       arg_types = [Ptr vector_struct;
                                    Sint32;
                                    Ptr Void];
                       extra_ptr_types = [];
                       lemmas_before = [];
                       lemmas_after = [];};]

let fixpoints =
  String.Map.of_alist_exn []

(* TODO: make external_ip symbolic *)
module Iface : Fspec_api.Spec =
struct
  let preamble = (In_channel.read_all "preamble.tmpl") ^
                 "void to_verify()\n\
                  /*@ requires true; @*/ \n\
                  /*@ ensures true; @*/\n{\n\
                  uint8_t received_on_port;\n\
                  uint32_t received_packet_type;\n\
                  struct user_buf the_received_packet;\n\
                  bool a_packet_received = false;\n\
                  struct user_buf sent_packet;\n\
                  uint8_t sent_on_port;\n\
                  uint32_t sent_packet_type;\n\
                  bool a_packet_sent = false;\n"
  let fun_types = fun_types
  let fixpoints = fixpoints
  let boundary_fun = "loop_invariant_produce"
  let finishing_fun = "loop_invariant_consume"
  let eventproc_iteration_begin = "loop_invariant_produce"
  let eventproc_iteration_end = "loop_invariant_consume"
  let user_check_for_complete_iteration =
    "" (*In_channel.read_all "forwarding_property.tmpl"*)
end

(* Register the module *)
let () =
  Fspec_api.spec := Some (module Iface) ;

