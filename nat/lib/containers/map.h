#ifndef _MAP_H_INCLUDED_
#define _MAP_H_INCLUDED_

typedef int map_keys_equality/*@<K>(predicate (void*; K) keyp) @*/(void* k1, void* k2);
//@ requires keyp(k1, ?kk1) &*& keyp(k2, ?kk2);
//@ ensures keyp(k1, kk1) &*& keyp(k2, kk2) &*& (0 == result ? (kk1 != kk2) : (kk1 == kk2));


/*@ predicate pred_arg4<t1,t2,t3,t4>(predicate (t1,t2,t3,t4) p) = true;
    predicate pred_arg2<t1,t2>(predicate (t1,t2) p) = true;
  @*/

/*@
  // map<kt> = list<pair<kt,int> >;

  predicate mapping<kt>(list<pair<kt,int> > m,
                        predicate (void*;kt) keyp,
                        fixpoint (kt,int,bool) recp,
                        fixpoint (kt,int) hash,
                        int capacity,
                        int* busybits,
                        void** keyps,
                        int* k_hashes,
                        int* values);

  fixpoint list<pair<kt,int> > empty_map_fp<kt>() { return nil; }

  fixpoint int map_get_fp<kt>(list<pair<kt,int> > m, kt key) {
    switch(m) {
      case nil: return default_value<int>();
      case cons(h,t):
        return (fst(h) == key ? snd(h) : map_get_fp(t, key));
    }
  }

  fixpoint bool map_has_fp<kt>(list<pair<kt,int> > m, kt key) {
    switch(m) {
      case nil: return false;
      case cons(h,t):
        return (fst(h) == key) || map_has_fp(t, key);
    }
  }

  fixpoint list<pair<kt,int> > map_put_fp<kt>(list<pair<kt,int> > m,
                                              kt key, int val) {
    return cons(pair(key,val), m);
  }

  fixpoint list<pair<kt,int> > map_erase_fp<kt>(list<pair<kt,int> > m, kt key) {
    switch(m) {
      case nil: return nil;
      case cons(h,t):
        return fst(h) == key ? t : cons(h, map_erase_fp(t, key));
    }
  }

  fixpoint int map_size_fp<kt>(list<pair<kt,int> > m) {
    return length(m);
  }
  @*/

/**
 * Values and keys are void*, and the actual keys and values should be managed
 * by the client application.
 *
 * I could not use integer keys, because need to operate with keys like
 * int_key/ext_key that are much bigger than a 32bit integer.
 */
void map_initialize/*@ <kt> @*/ (int* busybits, map_keys_equality* cmp,
                                 void** keyps, int* khs, int* vals,
                                 int capacity);
/*@ requires exists<kt>(_) &*&
             exists<fixpoint (kt,int)>(?hash) &*&
             [?fr]is_map_keys_equality<kt>(cmp, ?keyp) &*&
             exists<fixpoint(kt,int,bool)>(?recp) &*&
             ints(busybits, capacity, ?bbs) &*&
             pointers(keyps, capacity, ?kplist) &*&
             ints(vals, capacity, ?vallist) &*&
             ints(khs, capacity, ?khlist) &*&
             0 < capacity &*& 2*capacity < INT_MAX; @*/
/*@ ensures mapping<kt>(empty_map_fp(), keyp, recp, hash,
                        capacity, busybits, keyps,
                        khs, vals) &*&
            [fr]is_map_keys_equality<kt>(cmp, keyp); @*/

int map_get/*@ <kt> @*/(int* busybits, void** keyps, int* k_hashes, int* values,
                        void* keyp, map_keys_equality* eq, int hash, int* value,
                        int capacity);
/*@ requires mapping<kt>(?m, ?kp, ?recp, ?hsh, capacity, busybits,
                         keyps, k_hashes, values) &*&
             kp(keyp, ?k) &*&
             [?fr]is_map_keys_equality(eq, kp) &*&
             hsh(k) == hash &*&
             *value |-> ?v; @*/
/*@ ensures mapping<kt>(m, kp, recp, hsh, capacity, busybits,
                        keyps, k_hashes, values) &*&
            kp(keyp, k) &*&
            [fr]is_map_keys_equality(eq, kp) &*&
            (map_has_fp(m, k) ?
             (result == 1 &*&
              *value |-> ?nv &*&
              nv == map_get_fp(m, k) &*&
              true == recp(k, nv)):
             (result == 0 &*&
              *value |-> v)); @*/

int map_put/*@ <kt> @*/(int* busybits, void** keyps, int* k_hashes, int* values,
                        void* keyp, int hash, int value,
                        int capacity);
/*@ requires mapping<kt>(?m, ?kp, ?recp, ?hsh, capacity, busybits,
                         keyps, k_hashes, values) &*&
             kp(keyp, ?k) &*& true == recp(k, value) &*&
             hsh(k) == hash &*&
             false == map_has_fp(m, k); @*/
/*@ ensures true == recp(k, value) &*&
            (map_size_fp(m) < capacity ?
             (result == 1 &*&
              mapping<kt>(map_put_fp(m, k, value), kp, recp,
                          hsh,
                          capacity, busybits,
                          keyps, k_hashes, values)) :
             (result == 0 &*&
              kp(keyp, k) &*&
              mapping<kt>(m, kp, recp, hsh, capacity, busybits,
                          keyps, k_hashes, values))); @*/

int map_erase/*@ <kt> @*/(int* busybits, void** keyps, int* key_hashes,
                          void* keyp, map_keys_equality* eq, int hash,
                          int capacity);
/*@ requires mapping<kt>(?m, ?kp, ?recp, ?hsh, capacity, busybits,
                         keyps, key_hashes, ?values) &*&
             kp(keyp, ?k) &*&
             hsh(k) == hash; @*/
/*@ ensures kp(keyp, k) &*&
            (map_has_fp(m, k) ?
             (result == 1 &*&
              mapping<kt>(map_erase_fp(m, k), kp, recp, hsh,
                          capacity, busybits, keyps, key_hashes, values)) :
             (result == 0 &*&
              mapping<kt>(m, kp, recp, hsh,
                          capacity, busybits, keyps, key_hashes, values))); @*/

int map_size/*@ <kt> @*/(int* busybits, int capacity);
/*@ requires mapping<kt>(?m, ?kp, ?recp, ?hsh, capacity, busybits,
                         ?keyps, ?k_hashes, ?values); @*/
/*@ ensures mapping<kt>(m, kp, recp, hsh, capacity, busybits,
                        keyps, k_hashes, values) &*&
            result == map_size_fp(m);@*/

#endif //_MAP_H_INCLUDED_
