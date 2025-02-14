#
#   Copyright (c) 2010-2016, MIT Probabilistic Computing Project
#
#   Lead Developers: Dan Lovell and Jay Baxter
#   Authors: Dan Lovell, Baxter Eaves, Jay Baxter, Vikash Mansinghka
#   Research Leads: Vikash Mansinghka, Patrick Shafto
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

from __future__ import print_function
from libcpp cimport bool
from libcpp.vector cimport vector
from libcpp.string cimport string
from libcpp.map cimport map as c_map
from libcpp.set cimport set as c_set
from cython.operator import dereference

cimport numpy as np
np.import_array()


import collections
import numpy
import six
import pickle

import crosscat.src.utils.file_utils as fu
import crosscat.src.utils.general_utils as gu


cdef c_map[int, c_set[int]] empty_map_of_int_set():
    cdef c_map[int, c_set[int]] retval
    return retval


cdef double set_double(double& to_set, double value):
    (&to_set)[0] = value	# (&...)[0] works around Cython >=0.18 bug.
    return to_set


cdef vector[int] convert_int_vector_to_cpp(python_vector):
    cdef vector[int] ret_vec
    for value in python_vector:
        ret_vec.push_back(value)
    return ret_vec


cdef vector[string] convert_string_vector_to_cpp(python_vector):
    cdef vector[string] ret_vec
    cdef string s
    for value in python_vector:
        s = value if isinstance(value, bytes) else value.encode('utf-8')
        ret_vec.push_back(s)
    return ret_vec


cdef extern from "Matrix.h":
    cdef cppclass matrix[double]:
        size_t size1()
        size_t size2()
        double& operator()(size_t i, size_t j)
    matrix[double] *new_matrix "new matrix<double>" (size_t i, size_t j)
    void del_matrix "delete" (matrix *m)


cdef matrix[double]* convert_data_to_cpp(np.ndarray[np.float64_t, ndim=2] data):
    cdef int num_rows = data.shape[0]
    cdef int num_cols = data.shape[1]
    dataptr = new_matrix(num_rows, num_cols)
    cdef int i,j
    for i from 0 <= i < num_rows:
        for j from 0 <= j < num_cols:
            set_double(dereference(dataptr)(i,j), data[i,j])
    return dataptr


cdef extern from "State.h":
    cdef cppclass State:
        # Mutators.
        double insert_row(
            vector[double] row_data, int matching_row_idx, int row_idx)
        double transition(matrix[double] data)
        double transition_column_crp_alpha()
        double transition_features(matrix[double] data, vector[int] which_cols)
        double transition_column_hyperparameters(vector[int] which_cols)
        double transition_row_partition_hyperparameters(vector[int] which_cols)
        double transition_row_partition_assignments(
            matrix[double] data, vector[int] which_rows)
        double transition_views(matrix[double] data)
        double transition_view_i(int i, matrix[double] data)
        double transition_views_row_partition_hyper()
        double transition_views_col_hypers()
        double transition_views_zs(matrix[double] data)
        double calc_row_predictive_logp(vector[double] in_vd)

        # Getters.
        double get_column_crp_alpha()
        double get_column_crp_score()
        double get_data_score()
        double get_marginal_logp()
        vector[double] get_draw(int row_idx, int random_seed)
        int get_num_views()
        c_map[int, vector[int]] get_column_groups()
        string to_string(string join_str, bool top_level)
        double draw_rand_u()
        int draw_rand_i()

        # API helpers
        vector[c_map[string, double]] get_column_hypers()
        c_map[string, double] get_column_partition_hypers()
        vector[int] get_column_partition_assignments()
        vector[int] get_column_partition_counts()

        c_map[string, double] get_row_partition_model_hypers_i(int view_idx)
        c_map[int, c_set[int]] get_column_dependencies()
        c_map[int, c_set[int]] get_column_independencies()
        vector[int] get_row_partition_model_counts_i(int view_idx)
        vector[vector[c_map[string, double]]] get_column_component_suffstats_i(
            int view_idx)

        vector[vector[int]] get_X_D()
        void SaveResult()

    State *new_State "new State" (
        matrix[double] &data,
        vector[string] global_col_datatypes,
        vector[int] global_col_multinomial_counts,
        vector[int] global_row_indices,
        vector[int] global_col_indices,
        string col_initialization,
        string row_initialization,
        vector[double] ROW_CRP_ALPHA_GRID,
        vector[double] COLUMN_CRP_ALPHA_GRID,
        vector[double] S_GRID,
        vector[double] MU_GRID,
        int N_GRID,
        int SEED,
        int CT_KERNEL
    )

    State *new_State "new State" (
        matrix[double] &data,
        vector[string] global_col_datatypes,
        vector[int] global_col_multinomial_counts,
        vector[int] global_row_indices,
        vector[int] global_col_indices,
        c_map[int, c_map[string, double]] hypers_m,
        vector[vector[int]] column_partition,
        c_map[int, c_set[int]] col_ensure_dep,
        c_map[int, c_set[int]] col_ensure_ind,
        double column_crp_alpha,
        vector[vector[vector[int]]] row_partition_v,
        vector[double] row_crp_alpha_v,
        vector[double] ROW_CRP_ALPHA_GRID,
        vector[double] COLUMN_CRP_ALPHA_GRID,
        vector[double] S_GRID,
        vector[double] MU_GRID,
        int N_GRID,
        int SEED,
        int CT_KERNEL
    )

    void del_State "delete" (State *s)


def extract_column_types_counts(M_c):
    column_types = [
        column_metadata['modeltype']
        for column_metadata in M_c['column_metadata']
        ]
    event_counts = [
        len(column_metadata.get('value_to_code',[]))
        for column_metadata in M_c['column_metadata']
        ]
    return column_types, event_counts


def get_args_dict(args_list, vars_dict):
    args_dict = dict([(arg, vars_dict[arg]) for arg in args_list])
    return args_dict


transition_name_to_method_name_and_args = dict(
     column_partition_hyperparameter=
        ('transition_column_crp_alpha', []),
     column_partition_assignments=
        ('transition_features', ['c']),
     column_hyperparameters=
        ('transition_column_hyperparameters', ['c']),
     row_partition_hyperparameters=
        ('transition_row_partition_hyperparameters', ['c']),
     row_partition_assignments=
        ('transition_row_partition_assignments', ['r']),
     )

def get_all_transitions_permuted(seed):
    which_transitions = list(transition_name_to_method_name_and_args.keys())  # Convert dict_keys to a list
    print('which_transitions', which_transitions)  # For debugging purposes

    # Generate a random permutation of indices for the transition names
    num_transitions = len(which_transitions)
    if seed is not None:
        random_state = numpy.random.RandomState(seed)
    else:
        random_state = numpy.random.RandomState()
    permutation_indices = random_state.permutation(num_transitions)

    # Rearrange the transition names based on the permutation indices
    permuted_transitions = [which_transitions[i] for i in permutation_indices]

    return permuted_transitions

def process_mc_dict(item, encode_keys=False):
    """
    Recursively process an item to ensure all strings are encoded to bytes.
    This method handles dictionaries, lists, and standalone strings.
    """
    if isinstance(item, dict):
        # Process dictionaries: encode keys and values or recursively process them
        if encode_keys:
            return {process_string(key): process_mc_dict(value, encode_keys) for key, value in item.items()}
        else:
            return {key.decode('utf-8') if isinstance(key, bytes) else key: process_mc_dict(value, encode_keys) for key, value in item.items()}
    elif isinstance(item, list):
        # Process lists: encode strings or recursively process items
        return [process_mc_dict(i, encode_keys) for i in item]
    elif isinstance(item, str):
        # Directly convert strings to bytes
        return process_string(item)
    else:
        # Return the item unchanged if it's not a dict, a list, or a string
        return item

def process_string(string):
    """
    Encode a string to bytes using UTF-8 encoding.
    """
    return string.encode('utf-8') if isinstance(string, str) else string


cdef class p_State:

    cdef State *thisptr
    cdef matrix[double] *dataptr
    cdef vector[int] gri
    cdef vector[int] gci
    cdef vector[string] column_types
    cdef vector[int] event_counts
    cdef np.ndarray T_array
    cdef dict _M_c  # Assuming M_c is a dictionary


    property M_c:
        def __get__(self):
            return self._M_c
        def __set__(self, value):
            self._M_c = value


    def __cinit__(
            self, M_c, T, X_L=None, X_D=None,
            initialization='from_the_prior', row_initialization=-1,
            ROW_CRP_ALPHA_GRID=(), COLUMN_CRP_ALPHA_GRID=(),
            S_GRID=(), MU_GRID=(), N_GRID=31, SEED=0, CT_KERNEL=0
        ):

        column_types, event_counts = extract_column_types_counts(M_c)

        M_c_bytes = process_mc_dict(M_c, encode_keys = False)




        global_row_indices = range(len(T))
        global_col_indices = range(len(T[0]))

        # FIXME: keeping TWO copies of the data here
        self.T_array = numpy.array(T)
        #print(1)
        self.dataptr = convert_data_to_cpp(self.T_array)
        #print(11)
        self.column_types = convert_string_vector_to_cpp(column_types)
        #print(111)
        self.event_counts = convert_int_vector_to_cpp(event_counts)
        #print(1111)
        self.gri = convert_int_vector_to_cpp(global_row_indices)
        #print(11111)
        self.gci = convert_int_vector_to_cpp(global_col_indices)
        #print(11111)
        self.M_c = M_c_bytes
        #print('yay')


        must_initialize = X_L is None
        if must_initialize:
            col_initialization = initialization
            if row_initialization == -1:
                row_initialization = initialization
            self.thisptr = new_State(
                dereference(self.dataptr),
                self.column_types,
                self.event_counts,
                self.gri, self.gci,
                col_initialization,
                row_initialization,
                ROW_CRP_ALPHA_GRID,
                COLUMN_CRP_ALPHA_GRID,
                S_GRID, MU_GRID,
                N_GRID, SEED, CT_KERNEL
            )
        else:
            # # !!! MUTATES X_L !!!
            desparsify_X_L(M_c, X_L)
            constructor_args = transform_latent_state_to_constructor_args(
                X_L, X_D)
            #print(constructor_args)
            constructor_args = process_mc_dict(constructor_args, encode_keys = False)
            #print('transformed', constructor_args)
            #print('hypers_m', constructor_args['hypers_m'])
            hypers_m = process_mc_dict(constructor_args['hypers_m'], encode_keys = True)
            column_partition = constructor_args['column_partition']
            column_crp_alpha = constructor_args['column_crp_alpha']
            row_partition_v = constructor_args['row_partition_v']
            row_crp_alpha_v = constructor_args['row_crp_alpha_v']
            col_ensure_dep = constructor_args['col_ensure_dep']
            col_ensure_ind = constructor_args['col_ensure_ind']

            if col_ensure_dep is None:
                col_ensure_dep = empty_map_of_int_set()
                col_ensure_ind = empty_map_of_int_set()

            self.thisptr = new_State(
                dereference(self.dataptr),
                self.column_types,
                self.event_counts,
                self.gri, self.gci,
                hypers_m,
                column_partition,
                col_ensure_dep,
                col_ensure_ind,
                column_crp_alpha,
                row_partition_v, row_crp_alpha_v,
                ROW_CRP_ALPHA_GRID,
                COLUMN_CRP_ALPHA_GRID,
                S_GRID, MU_GRID,
                N_GRID, SEED, CT_KERNEL
            )

    def __dealloc__(self):
        del_matrix(self.dataptr)
        del_State(self.thisptr)

    def __repr__(self):
        print_tuple = (
            self.dataptr.size1(),
            self.dataptr.size2(),
            self.thisptr.to_string(";".encode("utf-8"), False),
        )
        return("State[%s, %s]:\n%s" % print_tuple)

    def to_string(self, join_str='\n', top_level=False):
         return self.thisptr.to_string(join_str, top_level)

    # getters
    def get_column_groups(self):
        return self.thisptr.get_column_groups()
    def get_column_crp_alpha(self):
        return self.thisptr.get_column_crp_alpha()
    def get_column_crp_score(self):
        return self.thisptr.get_column_crp_score()
    def get_data_score(self):
        return self.thisptr.get_data_score()
    def get_marginal_logp(self):
        return self.thisptr.get_marginal_logp()
    def get_num_views(self):
        return self.thisptr.get_num_views()
    def calc_row_predictive_logp(self, in_vd):
        return self.thisptr.calc_row_predictive_logp(in_vd)
    def get_draw(self, row_idx, random_seed):
        return self.thisptr.get_draw(row_idx, random_seed)

    # get_X_L helpers helpers
    def get_row_partition_model_i(self, view_idx):
          hypers = self.thisptr.get_row_partition_model_hypers_i(view_idx)
          counts = self.thisptr.get_row_partition_model_counts_i(view_idx)
          row_partition_model_i = dict()
          row_partition_model_i['hypers'] = hypers
          row_partition_model_i['counts'] = counts
          return row_partition_model_i

    def get_column_names_i(self, view_idx):
        idx_to_name = self.M_c['idx_to_name']
        column_groups = self.thisptr.get_column_groups()

        column_indices_i = column_groups[view_idx]
        column_indices_i = map(str, column_indices_i)
        column_names_i = []
        for idx in column_indices_i:
             if idx not in idx_to_name:
                  print('%r not in %r' % (idx, idx_to_name))
             value = idx_to_name[idx]
             column_names_i.append(value)

        return column_names_i

    def get_column_component_suffstats_i(self, view_idx):
         column_component_suffstats = \
             self.thisptr.get_column_component_suffstats_i(view_idx)
         # FIXME: make this actually work
         #        should sparsify here rather than later in get_X_L
         # column_names = self.get_column_names_i(view_idx)
         # for col_name, column_component_suffstats_i in \
         #          zip(column_names, column_component_suffstats):
         #     modeltype = get_modeltype_from_name(self.M_c, col_name)
         #     if modeltype == 'symmetric_dirichlet_discrete':
         #         sparsify_column_component_suffstats(column_component_suffstats_i)
         return column_component_suffstats
    def get_view_state_i(self, view_idx):
          row_partition_model = self.get_row_partition_model_i(view_idx)
          column_names = self.get_column_names_i(view_idx)
          column_component_suffstats = \
              self.get_column_component_suffstats_i(view_idx)
          view_state_i = dict()
          view_state_i['row_partition_model'] = row_partition_model
          view_state_i['column_names'] = list(column_names)
          view_state_i['column_component_suffstats'] = \
              column_component_suffstats
          return view_state_i
    # get_X_L helpers
    def get_column_partition(self):
        hypers = self.thisptr.get_column_partition_hypers()
        assignments = self.thisptr.get_column_partition_assignments()
        counts = self.thisptr.get_column_partition_counts()
        column_partition = dict()
        column_partition['hypers'] = hypers
        column_partition['assignments'] = assignments
        column_partition['counts'] = counts
        return column_partition
    def get_column_hypers(self):
        return self.thisptr.get_column_hypers()
    def get_view_state(self):
        view_state = []
        for view_idx in range(self.get_num_views()):
            view_state_i = self.get_view_state_i(view_idx)
            view_state.append(view_state_i)
        return view_state

    def get_col_ensure_dep(self):
        retval = self.thisptr.get_column_dependencies()
        if len(retval) == 0:
            return None
        else:
            return retval

    def get_col_ensure_ind(self):
        retval = self.thisptr.get_column_independencies()
        if len(retval) == 0:
            return None
        else:
            return retval

    # mutators
    def insert_row(self, row_data, matching_row_idx, row_idx=-1):
        return self.thisptr.insert_row(row_data, matching_row_idx, row_idx)

    def transition(
            self, which_transitions=(), n_steps=1, c=(), r=(),
            max_iterations=-1, max_time=-1, progress=None,
            diagnostic_func_dict=None, diagnostics_dict=None,
            diagnostics_every_N=None,
        ):

        def _proportion_done(N, S, iters, elapsed):
            p_seconds = elapsed / S if S != -1 else 0
            p_iters = float(iters) / N
            return max(p_iters, p_seconds)

        if diagnostics_dict is None:
            diagnostics_dict = collections.defaultdict(list)
        if diagnostic_func_dict is None:
            diagnostic_func_dict = dict()

        seed = None
        score_delta = 0
        if len(which_transitions) == 0:
            seed = self.thisptr.draw_rand_i()
            which_transitions = get_all_transitions_permuted(seed)

        with gu.Timer('transition', verbose=False) as timer:
            step_idx = 0
            while True:

                for which_transition in which_transitions:
                    elapsed_secs = timer.get_elapsed_secs()
                    p = _proportion_done(
                        n_steps, max_time, step_idx, elapsed_secs)
                    if progress:
                        progress(n_steps, max_time, step_idx, elapsed_secs)
                    if 1 <= p:
                       break

                    method_name_and_args = \
                        transition_name_to_method_name_and_args.get(
                            which_transition)

                    if method_name_and_args is not None:
                        method_name, args_list = method_name_and_args
                        which_method = getattr(self, method_name)
                        args_dict = get_args_dict(args_list, locals())
                        score_delta += which_method(**args_dict)
                    else:
                        print_str = 'INVALID TRANSITION TYPE TO ' \
                            'State.transition: %s' % which_transition
                        print(print_str)
                else:
                    step_idx += 1
                    if (diagnostics_every_N) and \
                            (step_idx % diagnostics_every_N == 0):
                        for diagnostic_name, diagnostic_func in\
                                six.iteritems(diagnostic_func_dict):
                            diagnostic_value = diagnostic_func(self)
                            diagnostics_dict[diagnostic_name].append(
                                diagnostic_value)
                    continue

                if progress:
                    progress(
                        n_steps, max_time, step_idx, elapsed_secs, end=True)

                break

        return score_delta

    def transition_column_crp_alpha(self):
        return self.thisptr.transition_column_crp_alpha()
    def transition_features(self, c=()):
        return self.thisptr.transition_features(dereference(self.dataptr), c)
    def transition_column_hyperparameters(self, c=()):
        return self.thisptr.transition_column_hyperparameters(c)
    def transition_row_partition_hyperparameters(self, c=()):
        return self.thisptr.transition_row_partition_hyperparameters(c)
    def transition_row_partition_assignments(self, r=()):
        return self.thisptr.transition_row_partition_assignments(
            dereference(self.dataptr), r)
    def transition_views(self):
        return self.thisptr.transition_views(dereference(self.dataptr))
    def transition_view_i(self, i):
        return self.thisptr.transition_view_i(i, dereference(self.dataptr))
    def transition_views_col_hypers(self):
        return self.thisptr.transition_views_col_hypers()
    def transition_views_row_partition_hyper(self):
        return self.thisptr.transition_views_row_partition_hyper()
    def transition_views_zs(self):
        return self.thisptr.transition_views_zs(dereference(self.dataptr))

    # API getters
    def get_X_D(self):
        return self.thisptr.get_X_D()

    def get_X_L(self):
        column_partition = self.get_column_partition()
        column_hypers = self.get_column_hypers()
        view_state = self.get_view_state()

        # Need to convert from c_map[int c_set[int] to dict(string:list).
        col_ensure_dep = self.get_col_ensure_dep()
        col_ensure_ind = self.get_col_ensure_ind()

        if col_ensure_dep is None:
            col_ensure_dep_json = {}
        else:
            col_ensure_dep_json = {
                str(k):list(v) for (k,v) in col_ensure_dep.items()
            }
        if col_ensure_ind is None:
           col_ensure_ind_json = {}
        else:
            col_ensure_ind_json = {
                str(k):list(v) for (k,v) in col_ensure_ind.items()
            }

        X_L = dict()
        X_L['column_partition'] = column_partition
        X_L['column_hypers'] = column_hypers
        X_L['view_state'] = view_state
        if col_ensure_dep is not None or col_ensure_ind is not None:
            X_L['col_ensure'] = dict()
            X_L['col_ensure']['dependent'] = col_ensure_dep_json
            X_L['col_ensure']['independent'] = col_ensure_ind_json

        sparsify_X_L(self.M_c, X_L)
        return X_L

    def save(self, filename, dir='', **kwargs):
        save_dict = dict(
            X_L=self.get_X_L(),
            X_D=self.get_X_D(),
        )
        save_dict.update(**kwargs)
        fu.pickle(save_dict, filename, dir=dir)


def indicator_list_to_list_of_list(indicator_list):
    list_of_list = []
    num_clusters = max(indicator_list) + 1
    import numpy
    for cluster_idx in range(num_clusters):
        which_rows = numpy.array(indicator_list) == cluster_idx
        list_of_list.append(numpy.nonzero(which_rows)[0])
    return list_of_list


def floatify_dict(in_dict):
    for key in in_dict:
        in_dict[key] = float(in_dict[key])
    return in_dict


def floatify_dict_dict(in_dict):
    for key in in_dict:
        in_dict[key] = floatify_dict(in_dict[key])
    return in_dict


def extract_row_partition_alpha(view_state):
    hypers = view_state['row_partition_model']['hypers']
    alpha = hypers.get('alpha')
    if alpha is None:
        log_alpha = hypers['log_alpha']
        alpha = numpy.exp(log_alpha)
    return alpha


def transform_latent_state_to_constructor_args(X_L, X_D):
    num_rows = len(X_D[0])
    num_cols = len(X_L['column_hypers'])

    global_row_indices = range(num_rows)
    global_col_indices = range(num_cols)
    hypers_m = dict(zip(global_col_indices, X_L['column_hypers']))
    hypers_m = floatify_dict_dict(hypers_m)
    column_indicator_list = X_L['column_partition']['assignments']
    column_partition = indicator_list_to_list_of_list(column_indicator_list)
    column_crp_alpha = X_L['column_partition']['hypers']['alpha']
    row_partition_v = map(indicator_list_to_list_of_list, X_D)
    row_crp_alpha_v = map(extract_row_partition_alpha, X_L['view_state'])

    # Need to convert from dict(string:list) to c_map[int c_set[int].
    if X_L.get('col_ensure', None) is None:
        col_ensure_dep = empty_map_of_int_set()
        col_ensure_ind = empty_map_of_int_set()
    else:
        col_ensure_dep_json = X_L['col_ensure'].get('dependent', None)
        if col_ensure_dep_json is None:
            col_ensure_dep = empty_map_of_int_set()
        else:
            col_ensure_dep = {
                int(k):set(v) for (k,v) in col_ensure_dep_json.items()
            }
        col_ensure_ind_json = X_L['col_ensure'].get('independent', None)
        if col_ensure_ind_json is None:
            col_ensure_ind = empty_map_of_int_set()
        else:
            col_ensure_ind = {
                int(k):set(v) for (k,v) in col_ensure_ind_json.items()
            }

    n_grid = 31
    seed = 0
    ct_kernel=0

    constructor_args = dict()
    constructor_args['global_row_indices'] = global_row_indices
    constructor_args['global_col_indices'] = global_col_indices
    constructor_args['hypers_m'] = hypers_m
    constructor_args['column_partition'] = column_partition
    constructor_args['column_crp_alpha'] = column_crp_alpha
    constructor_args['row_partition_v'] = row_partition_v
    constructor_args['row_crp_alpha_v'] = row_crp_alpha_v
    constructor_args['N_GRID'] = n_grid
    constructor_args['SEED'] = seed
    constructor_args['CT_KERNEL'] = ct_kernel
    constructor_args['col_ensure_dep'] = col_ensure_dep
    constructor_args['col_ensure_ind'] = col_ensure_ind
    return constructor_args


def without_zero_values(dict_in):
    return {k: v for k, v in six.iteritems(dict_in) if v != 0}


def insert_zero_values(dict_in, N_keys):
    for key in range(N_keys):
        key_str = str(key)
        if key_str not in dict_in:
            dict_in[key_str] = 0.0
    return dict_in


def sparsify_column_component_suffstats(column_component_suffstats):
    for idx, suffstats_i in enumerate(column_component_suffstats):
        suffstats_i = without_zero_values(suffstats_i)
        column_component_suffstats[idx] = suffstats_i
    return None


def desparsify_column_component_suffstats(
        column_component_suffstats, N_keys):
    for idx, suffstats_i in enumerate(column_component_suffstats):
        insert_zero_values(suffstats_i, N_keys)
    return None


def get_column_component_suffstats_by_global_col_idx(M_c, X_L, col_idx):
    col_name = M_c['idx_to_name'][str(col_idx)]
    view_idx = X_L['column_partition']['assignments'][col_idx]
    view_state_i = X_L['view_state'][view_idx]
    within_view_idx = view_state_i['column_names'].index(col_name)
    column_component_suffstats_i = \
        view_state_i['column_component_suffstats'][within_view_idx]
    return column_component_suffstats_i


def sparsify_X_L(M_c, X_L):
    for col_idx, col_i_metadata in enumerate(M_c['column_metadata']):
        modeltype = col_i_metadata['modeltype']
        if modeltype != 'symmetric_dirichlet_discrete':
            continue
        column_component_suffstats_i = \
            get_column_component_suffstats_by_global_col_idx(
                M_c, X_L, col_idx)
        sparsify_column_component_suffstats(column_component_suffstats_i)
    return None

def desparsify_X_L(M_c, X_L):
    for col_idx, col_i_metadata in enumerate(M_c['column_metadata']):
        modeltype = col_i_metadata['modeltype']
        if modeltype != 'symmetric_dirichlet_discrete':
            continue
        column_component_suffstats_i = \
            get_column_component_suffstats_by_global_col_idx(
                M_c, X_L, col_idx)
        N_keys = len(col_i_metadata['value_to_code'])
        desparsify_column_component_suffstats(
            column_component_suffstats_i, N_keys)
    return None


def get_modeltype_from_name(M_c, col_name):
    global_col_idx = M_c['name_to_idx'][col_name]
    modeltype = M_c['column_metadata'][global_col_idx]['modeltype']
    return modeltype
