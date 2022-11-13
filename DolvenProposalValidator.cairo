%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
    get_block_timestamp,
)
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_not_equal,
    assert_nn_le,
    split_felt,
    assert_lt_felt,
    assert_le_felt,
    assert_le,
    unsigned_div_rem,
    signed_div_rem,
)
from starkware.cairo.common.uint256 import Uint256, uint256_eq, uint256_le, uint256_lt
from contracts.openzeppelin.security.safemath import SafeUint256
from starkware.cairo.common.math_cmp import is_le, is_not_zero, is_nn, is_in_range, is_nn_le
from contracts.openzeppelin.token.ERC20.interfaces.IERC20 import IERC20
from contracts.openzeppelin.access.ownable import Ownable
from contracts.openzeppelin.security.pausable import Pausable
from contracts.openzeppelin.security.reentrancy_guard import ReentrancyGuard
from contracts.Interfaces.IDolvenGovernance import IDolvenGovernance
from contracts.Interfaces.IDolvenVault import IDolvenVault

const ONE_HUNDRED_WITH_PRECISION = 10000;
// percentes should be multiplied with 100

@storage_var
func PROPOSITION_THRESHOLD() -> (res: Uint256) {
}

@storage_var
func VOTE_DIFFERENTIAL() -> (res: Uint256) {
}

@storage_var
func MINIMUM_QUORUM() -> (res: Uint256) {
}

@storage_var
func VOTING_TYPE() -> (res: felt) {
}
// Type 0 == Every user has equal voting power
// Type 1 == Every user has different voting power


    @external
    func initializer_validator{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _PROPOSITION_THRESHOLD: Uint256,
        _VOTING_DURATION: felt,
        _VOTE_DIFFERENTIAL: Uint256,
        _MINIMUM_QUORUM: Uint256,
        _VOTING_TYPE: felt,
    ) {
        MINIMUM_QUORUM.write(_MINIMUM_QUORUM);
        VOTE_DIFFERENTIAL.write(_VOTE_DIFFERENTIAL);
        PROPOSITION_THRESHOLD.write(_PROPOSITION_THRESHOLD);
        VOTING_TYPE.write(_VOTING_TYPE);
        return ();
    }

    // #Viewers

    @view
    func validateCreatorOfProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, user_account: felt
    ) -> (is_user_valid: felt) {
        let result: felt = isPropositionPowerEnough(strategy, user_account);
        return (result,);
    }

    @view
    func checkProposalType{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        proposal_type: felt
    ) -> (is_type_valid: felt) {
        if (proposal_type == 1) {
            return (1,);
        } else {
            if (proposal_type == 0) {
                return (1,);
            } else {
                return (0,);
            }
        }
    }

    @view
    func getVotingPower{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, user_account: felt
    ) -> (user_vote_power: Uint256) {
        alloc_locals;
        let _voting_type: felt = VOTING_TYPE.read();
        if (_voting_type == 0) {
            let zero_as_uint256: Uint256 = Uint256(0, 0);
            let (time) = get_block_timestamp();
            let user_ticket_count: Uint256 = IDolvenVault.get_userTicketCount(
                strategy, user_account, time
            );
            let res: felt = uint256_lt(zero_as_uint256, user_ticket_count);
            with_attr error_message("DolvenValidator::getVotingPower TICKET_AMOUNT_CANNOT_BE_ZERO") {
                assert res = 1;
            }
            return (user_ticket_count,);
        } else {
            let one: felt = 1;
            let one_as_uint256: Uint256 = felt_to_uint256(one);
            return (one_as_uint256,);
        }
    }

    @view
    func isProposalPassed{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, proposal_id: felt
    ) -> (is_passed: felt) {
        alloc_locals;
        let is_quorumValid: felt = is_quorum_valid(strategy, proposal_id);
        let _isVoteDifferentialValid: felt = isVoteDifferentialValid(strategy, proposal_id);
        let sum: felt = is_quorumValid + _isVoteDifferentialValid;
        if (sum == 2) {
            return (1,);
        } else {
            return (0,);
        }
    }

    @view
    func get_min_votingPowerNeeded{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        voting_supply: Uint256
    ) -> (min_power: Uint256) {
        alloc_locals;
        let _MINIMUM_QUORUM: Uint256 = MINIMUM_QUORUM.read();
        let min_power: Uint256 = SafeUint256.mul(voting_supply, _MINIMUM_QUORUM);
        let percent_base: Uint256 = felt_to_uint256(ONE_HUNDRED_WITH_PRECISION);
        let min_power: Uint256 = SafeUint256.div_rem(min_power, percent_base);
        return (min_power,);
    }

    // # Internal Functions

    func isVoteDifferentialValid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, proposal_id: felt
    ) -> (res: felt) {
        alloc_locals;
        let _vote_differential: Uint256 = VOTE_DIFFERENTIAL.read();
        let (proposal_details) = IDolvenGovernance.returnProposalByNonce(strategy, proposal_id);
        let (time) = get_block_timestamp();
        let voting_supply: Uint256 = IDolvenVault.get_totalLockedTicket_byTime(
            proposal_details.strategy, time
        );
        // #How much percent of total votes is belong to "for"
        let percent_base: Uint256 = felt_to_uint256(ONE_HUNDRED_WITH_PRECISION);
        let for_votes_value: Uint256 = SafeUint256.mul(proposal_details.forVotes, percent_base);
        let for_votes_value: Uint256 = SafeUint256.div_rem(for_votes_value, voting_supply);

        let percent_base: Uint256 = felt_to_uint256(ONE_HUNDRED_WITH_PRECISION);
        let against_votes: Uint256 = SafeUint256.mul(proposal_details.againstVotes, percent_base);
        let against_votes: Uint256 = SafeUint256.div_rem(against_votes, voting_supply);
        let against_votes: Uint256 = SafeUint256.add(against_votes, _vote_differential);
        let is_valid: felt = uint256_lt(against_votes, for_votes_value);
        return (is_valid,);
    }

    func is_quorum_valid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, proposal_id: felt
    ) -> (res: felt) {
        alloc_locals;
        let (proposal_details) = IDolvenGovernance.returnProposalByNonce(strategy, proposal_id);
        let (time) = get_block_timestamp();
        let voting_supply: Uint256 = IDolvenVault.get_totalLockedTicket_byTime(
            proposal_details.strategy, time
        );
        let min_votingPowerNeeded: Uint256 = get_min_votingPowerNeeded(voting_supply);
        let is_valid: felt = uint256_lt(min_votingPowerNeeded, proposal_details.forVotes);
        return (is_valid,);
    }

    func isPropositionPowerEnough{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, user_account: felt
    ) -> (res: felt) {
        alloc_locals;
        let (time) = get_block_timestamp();
        let user_ticket_count: Uint256 = IDolvenVault.get_userTicketCount(strategy, user_account, time);
        let total_locked_ticket_count: Uint256 = IDolvenVault.get_totalLockedTicket_byTime(
            strategy, time
        );
        let _minimumPropositionPowerNeeded: Uint256 = getMinimumPropositionPowerNeeded(
            total_locked_ticket_count
        );
        let is_user_valid: felt = uint256_lt(_minimumPropositionPowerNeeded, user_ticket_count);
        return (is_user_valid,);
    }

    func felt_to_uint256{range_check_ptr}(x) -> (uint_x: Uint256) {
        let (high, low) = split_felt(x);
        return (Uint256(low=low, high=high),);
    }

    func getMinimumPropositionPowerNeeded{
        syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
    }(total_locked_ticket_count: Uint256) -> (res: Uint256) {
        let _PROPOSITION_THRESHOLD: Uint256 = PROPOSITION_THRESHOLD.read();
        let min_value: Uint256 = SafeUint256.mul(total_locked_ticket_count, _PROPOSITION_THRESHOLD);
        let percent_base: Uint256 = felt_to_uint256(ONE_HUNDRED_WITH_PRECISION);
        let min_value: Uint256 = SafeUint256.div_rem(min_value, percent_base);
        return (min_value,);
    }
