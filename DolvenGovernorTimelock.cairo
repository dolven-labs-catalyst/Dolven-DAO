%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
    get_block_timestamp,
    call_contract
)
from starkware.cairo.common.hash import hash2
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
// upper threhold of delay, in seconds
@storage_var
func MAXIMUM_DELAY() -> (res: felt) {
}
// lower threshold of delay, in seconds
@storage_var
func MINUMUM_DELAY() -> (res: felt) {
}

// Minimum time between queueing and execution of proposal
@storage_var
func DELAY() -> (res: felt) {
}
// Delay before voting begin
@storage_var
func VOTING_DELAY() -> (res: felt) {
}
// Time after delay while a proposal can be executed
@storage_var
func GRACE_PERIOD() -> (res: felt) {
}
// Main Governance of Dolven Labs
@storage_var
func GOVERNANCE_ADDRESS() -> (res: felt) {
}
// Total voting duration
@storage_var
func VOTING_DURATION() -> (res: felt) {
}

@storage_var
func _queuedTransactions(action_hash : felt) -> (res: felt) {
}

@event
func QueuedAction(actionHash: felt, target: felt, selector: felt, calldata : felt, execution_time : felt) {
}

@event
func CancelledAction(actionHash: felt, target: felt, selector: felt, calldata : felt, execution_time : felt) {
}
 
    // # Initializer
    @external
    func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(   
        governance_address: felt,
        gracePeriod: felt,
        minumumDelay: felt,
        maximumDelay: felt,
        delay: felt,
        voting_delay: felt){
        alloc_locals;
        let is_delay_shorter_than_max: felt = is_le(minumumDelay, delay);
        let is_delay_longer_than_max: felt = is_le(delay, maximumDelay);
        with_attr error_message("DELAY_SHORTER_THAN_MINIMUM") {
            assert is_delay_shorter_than_max = 1;
        }
        with_attr error_message("DELAY_LONGER_THAN_MAXIMUM") {
            assert is_delay_longer_than_max = 1;
        }
        let (deployer) = get_caller_address();
        Ownable.initializer(deployer);
        GRACE_PERIOD.write(gracePeriod);
        MINUMUM_DELAY.write(minumumDelay);
        MAXIMUM_DELAY.write(maximumDelay);
        DELAY.write(delay);
        VOTING_DELAY.write(voting_delay);
        GOVERNANCE_ADDRESS.write(governance_address);
        return ();
    }

    // #Viewers

    @view
    func getDelay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (delay: felt) {
        let delay: felt = DELAY.read();
        return (delay,);
    }

    @view
    func getGovernance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        address: felt
    ) {
        let address: felt = GOVERNANCE_ADDRESS.read();
        return (address,);
    }

    @view
    func getVotingDelay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        delay: felt
    ) {
        let voting_delay: felt = VOTING_DELAY.read();
        return (voting_delay,);
    }

    @view
    func getVotingDuration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
        delay: felt
    ) {
        let voting_duration: felt = VOTING_DURATION.read();
        return (voting_duration,);
    }

    @view
    func isProposalOverGracePeriod{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        proposal_id: felt
    ) -> (status: felt) {
        alloc_locals;
        let _governanceAddress: felt = GOVERNANCE_ADDRESS.read();
        let (proposal_details) = IDolvenGovernance.returnProposalByNonce(
            _governanceAddress, proposal_id
        );
        let (time) = get_block_timestamp();
        let _gracePeriod: felt = GRACE_PERIOD.read();
        let condition: felt = _gracePeriod + proposal_details.executionTime;
        let res: felt = is_nn_le(condition, time);
        return (res,);
    }

   
    // #Externals
    @external
    func executeTransaction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _proposal_id : felt, target_index : felt, calldata_size: felt, index : felt
    ) {
        alloc_locals;
        onlyGovernance();
        let governance_address : felt = GOVERNANCE_ADDRESS.read(); 
        let (_calldata_data_len : felt, _calldata_data : felt*) = returnCalldata(_proposal_id, calldata_size, target_index, 0);
        let target : felt = IDolvenGovernance.return_proposal_targets(governance_address, _proposal_id, target_index);
        let selector : felt = IDolvenGovernance.return_proposal_selectors(governance_address, _proposal_id, target_index);
   
        if(index == calldata_size){
        return();
        }

        let reversed_calldata : felt* = _calldata_data - _calldata_data_len;
        
        let response = call_contract(
        contract_address=target,
        function_selector=selector,
        calldata_size=_calldata_data_len,
        calldata=reversed_calldata,
        );

        executeTransaction(_proposal_id, target_index, calldata_size, index + 1);
        return(); 
    }
   

    @external
    func cancelTransaction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        proposal_target : felt, _proposal_selector : felt, _proposal_single_calldata : felt, executionTime : felt
    ) {
        onlyGovernance();

        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(executionTime, proposal_target);
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, _proposal_selector);
        let (action_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, _proposal_single_calldata);

        _queuedTransactions.write(action_hash, FALSE);
        CancelledAction.emit(actionHash=action_hash, target=proposal_target, selector=_proposal_selector, calldata=_proposal_single_calldata, execution_time=executionTime);
        return();
    }

    @external
    func queueTransaction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        proposal_target : felt, _proposal_selector : felt, _proposal_single_calldata : felt, executionTime : felt
    ) {
        onlyGovernance();
        let (delay) = DELAY.read();
        let (time) = get_block_timestamp();
        let delayed : felt = time + delay;
        with_attr error_message("EXECUTION_TIME_UNDERESTIMATED") {
            assert_nn_le(executionTime, delayed);
        }

        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(executionTime, proposal_target);
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, _proposal_selector);
        let (action_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, _proposal_single_calldata);

        _queuedTransactions.write(action_hash, TRUE);
        QueuedAction.emit(actionHash=action_hash, target=proposal_target, selector=_proposal_selector, calldata=_proposal_single_calldata, execution_time=executionTime);
        return();
    }



    @external
    func changeDelay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        delay_duration: felt
    ) -> (delay_duration: felt) {
        check_duration(delay_duration);
        Ownable.assert_only_owner();
        DELAY.write(delay_duration);
        return (delay_duration,);
    }

    @external
    func changeVotingDelay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        voting_delay: felt
    ) -> (voting_delay: felt) {
        Ownable.assert_only_owner();
        VOTING_DELAY.write(voting_delay);
        return (voting_delay,);
    }

    @external
    func changeGracePeriod{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        grace_time: felt
    ) -> (grace_time: felt) {
        Ownable.assert_only_owner();
        GRACE_PERIOD.write(grace_time);
        return (grace_time,);
    }

    @external
    func changeVotingDuration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        voting_duration: felt
    ) -> (voting_duration: felt) {
        Ownable.assert_only_owner();
        VOTING_DURATION.write(voting_duration);
        return (voting_duration,);
    }

    // #Internal Functions

     func returnCalldata{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _proposalId: felt, loop_size: felt, _targetId: felt, index : felt
    ) -> (calldataArray_len : felt, calldataArray : felt*) {
        alloc_locals;
        let (governance_address) = GOVERNANCE_ADDRESS.read(); 
        let single_calldata : felt = IDolvenGovernance.return_proposal_calldatas(governance_address, _proposalId, _targetId, index);
        
        if(index == loop_size){
        let calldata_array : felt* = alloc();
        return(0, calldata_array);
        }

        let (_calldataArray_len : felt, _calldataArray : felt*) = returnCalldata(_proposalId, loop_size, _targetId, index + 1);
        assert [_calldataArray] = single_calldata;
        return(_calldataArray_len + 1, _calldataArray + 1);
    }

    // # Modifier

    func onlyGovernance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
        let (msg_sender) = get_caller_address();
        with_attr error_message("ADDRESS_CANNOT_BE_ZERO") {
            assert_not_zero(msg_sender);
        }
        let (governance_address) = GOVERNANCE_ADDRESS.read();
        with_attr error_message("CALLER_MUST_BE_GOVERNANCE") {
            assert governance_address = msg_sender;
        }
        return();
    }

    func check_duration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        duration: felt
    ) {
        alloc_locals;
        let maximumDelay: felt = MAXIMUM_DELAY.read();
        let minumumDelay: felt = MINUMUM_DELAY.read();
        let is_delay_shorter_than_max: felt = is_le(minumumDelay, duration);
        let is_delay_longer_than_max: felt = is_le(duration, maximumDelay);
        with_attr error_message("DELAY_SHORTER_THAN_MINIMUM") {
            assert is_delay_shorter_than_max = 1;
        }
        with_attr error_message("DELAY_LONGER_THAN_MAXIMUM") {
            assert is_delay_longer_than_max = 1;
        }
        return ();
    }
