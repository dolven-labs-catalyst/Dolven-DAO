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
from contracts.Interfaces.ITicketManager import ITicketManager

const ONE_HUNDRED_WITH_PRECISION = 10000;
// percentes should be multiplied with 100

@storage_var
func PROPOSITION_THRESHOLD() -> (res: Uint256) {
}

@storage_var
func VOTE_DIFFERENTIAL() -> (res: Uint256) {
}

@storage_var
func TICKET_MANAGER() -> (res: felt) {
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
    func setTicketManager{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        ticketManager : felt
    ) {
        Ownable.assert_only_owner();
        TICKET_MANAGER.write(ticketManager);
        return();
    }

    @external
    func initializer_validator{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _PROPOSITION_THRESHOLD: Uint256,
        _VOTING_DURATION: felt,
        _VOTE_DIFFERENTIAL: Uint256,
        _MINIMUM_QUORUM: Uint256,
        _VOTING_TYPE: felt,
        deployer : felt
    ) {
        Ownable.initializer(deployer);
        MINIMUM_QUORUM.write(_MINIMUM_QUORUM);
        VOTE_DIFFERENTIAL.write(_VOTE_DIFFERENTIAL);
        PROPOSITION_THRESHOLD.write(_PROPOSITION_THRESHOLD);
        VOTING_TYPE.write(_VOTING_TYPE);
        return ();
    }

    // #Viewers


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
        user_account: felt, time : felt
    ) -> (user_vote_power: felt) {
        alloc_locals;
        let _voting_type: felt = VOTING_TYPE.read();
        if (_voting_type == 0) {
            let _ticketManager : felt = TICKET_MANAGER.read();
            let user_ticket_count: felt = ITicketManager._checkpointsLookup(
                _ticketManager, time, user_account, 1 
            );
            let res: felt = is_le(1, user_ticket_count);
            with_attr error_message("DolvenValidator::getVotingPower TICKET_AMOUNT_CANNOT_BE_ZERO") {
                assert res = TRUE;
            }
            return (user_ticket_count,);
        } else {
            return (1,);
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
        voting_supply: felt
    ) -> (min_power: felt) {
        alloc_locals;
        let _MINIMUM_QUORUM: felt = MINIMUM_QUORUM.read();
        let _min_power: felt = voting_supply * _MINIMUM_QUORUM;
        let (min_power: felt, _) = unsigned_div_rem(_min_power, ONE_HUNDRED_WITH_PRECISION);
        return (min_power,);
    }

    // # External functions

    @external
    func changeVotingType{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        type : felt
    ) {
        Ownable.assert_only_owner();
        VOTING_TYPE.write(type);
        return();
    }

    // # Internal Functions

    func isVoteDifferentialValid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, proposal_id: felt
    ) -> (res: felt) {
        alloc_locals;
        let _vote_differential: felt = VOTE_DIFFERENTIAL.read();
        let (proposal_details) = IDolvenGovernance.returnProposalByNonce(strategy, proposal_id);
        let (time) = get_block_timestamp();
        let _ticketManager : felt = TICKET_MANAGER.read();
        let voting_supply: felt = ITicketManager._checkpointsLookup(
            _ticketManager, 0, proposal_details.startTimestamp, 0
        );
        // #How much percent of total votes is belong to "for"
        let _for_votes_value: felt = proposal_details.forVotes * ONE_HUNDRED_WITH_PRECISION;
        let (for_votes_value : felt, _ ) = unsigned_div_rem(_for_votes_value, voting_supply);

        let __against_votes: felt = proposal_details.againstVotes * ONE_HUNDRED_WITH_PRECISION;
        let (_against_votes: felt, _) = unsigned_div_rem(__against_votes, voting_supply);
        let against_votes: felt = _against_votes + _vote_differential;
        let is_valid: felt = is_le(against_votes + 1, for_votes_value);
        return (is_valid,);
    }

    func is_quorum_valid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        strategy: felt, proposal_id: felt
    ) -> (res: felt) {
        alloc_locals;
        let (proposal_details) = IDolvenGovernance.returnProposalByNonce(strategy, proposal_id);
        let (time) = get_block_timestamp();
        let _ticketManager : felt = TICKET_MANAGER.read();
        let voting_supply: felt = ITicketManager._checkpointsLookup(
            _ticketManager, 0, proposal_details.startTimestamp, 0
        );
        let min_votingPowerNeeded: felt = get_min_votingPowerNeeded(voting_supply);
        let is_valid: felt = is_le(min_votingPowerNeeded + 1, proposal_details.forVotes);
        return (is_valid,);
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
