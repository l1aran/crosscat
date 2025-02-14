import numpy
#
import crosscat.src.utils.convergence_test_utils


def get_logscore(p_State):
    return p_State.get_marginal_logp()

def get_num_views(p_State):
    return len(p_State.get_X_D())

def get_column_crp_alpha(p_State):
    return p_State.get_column_crp_alpha()

def get_ari(p_State):
    # requires environment: {view_assignment_truth}
    # requires import: {crosscat.utils.convergence_test_utils}
    X_L = p_State.get_X_L()
    ctu = crosscat.utils.convergence_test_utils
    return ctu.get_column_ARI(X_L, view_assignment_truth)

def get_mean_test_ll(p_State):
    # requires environment {M_c, T, T_test}
    # requires import: {crosscat.utils.convergence_test_utils}
    X_L = p_State.get_X_L()
    X_D = p_State.get_X_D()
    ctu = crosscat.utils.convergence_test_utils
    return ctu.calc_mean_test_log_likelihood(M_c, T, X_L, X_D, T_test)

def get_column_partition_assignments(p_State):
    return p_State.get_X_L()['column_partition']['assignments']

def column_chain_to_ratio(column_chain_arr, j, i=0):
    chain_i_j = column_chain_arr[[i, j], :]
    is_same = numpy.diff(chain_i_j, axis=0)[0] == 0
    n_chains = len(is_same)
    is_same_count = sum(is_same)
    ratio = is_same_count / float(n_chains)
    return ratio

def column_partition_assignments_to_f_z_statistic(column_partition_assignments,
        j, i=0):
    iter_column_chain_arr = column_partition_assignments.transpose((1, 0, 2))
    helper = lambda column_chain_arr: column_chain_to_ratio(column_chain_arr, j, i)
    as_list = map(helper, iter_column_chain_arr)
    return numpy.array(as_list)[:, numpy.newaxis]

def default_reprocess_diagnostics_func(diagnostics_arr_dict):
    # This code formerly did stuff with the column partition
    # assignments after deleting it.  The stuff it did was apparently
    # unused, and caused trouble with one-column tables, so we have
    # removed it.  But until someone ascertains that it is safe to
    # leave the column partition assignments in, we'll continue
    # deleting it for now.
    # del diagnostics_arr_dict['column_partition_assignments']
    return diagnostics_arr_dict
