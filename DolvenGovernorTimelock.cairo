%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    call_contract,
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
from starkware.cairo.common.hash import hash2
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

@storage_var
func QUEUED_TRANSACTIONS(action_hash : felt) -> (res: felt) {
}

// Total voting duration
@storage_var
func VOTING_DURATION() -> (res: felt) {
}

@event
func CancelledAction(actionHash : felt, target : felt, data : felt) -> (){
}

@event
func QueuedAction(actionHash : felt, target : felt, data : felt) -> (){
}

@event
func ExecutedAction(actionHash : felt, target : felt, data : felt) -> (){
}

    // # Initializer
    @external
    func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(   
        governance_address: felt,
        gracePeriod: felt,
        minumumDelay: felt,
        maximumDelay: felt,
        delay: felt,
        voting_delay: felt,
        deployer : felt){
            alloc_locals;
            let is_delay_shorter_than_max: felt = is_le(minumumDelay, delay);
            let is_delay_longer_than_max: felt = is_le(delay, maximumDelay);
            with_attr error_message("DELAY_SHORTER_THAN_MINIMUM") {
                assert is_delay_shorter_than_max = 1;
            }
            with_attr error_message("DELAY_LONGER_THAN_MAXIMUM") {
                assert is_delay_longer_than_max = 1;
            }
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
    func cancelTransaction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _proposalId : felt, index : felt, execution_time : felt
    ) {
        _onlyGovernance();
        let (governance) = GOVERNANCE_ADDRESS.read();
      
        let (proposal_execution_length) = IDolvenGovernance.returnExecutionLength(governance, _proposalId);
        let (proposalTarget) = IDolvenGovernance.returnProposalTarget(governance, _proposalId, index);
        let (proposalSelector) = IDolvenGovernance.returnProposalSelector(governance, _proposalId, index);
        let (proposalCalldata) = IDolvenGovernance.returnProposalCalldata(governance, _proposalId, index);

        //pedersen hash
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(execution_time, proposalTarget);
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, proposalSelector);
        let (action_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, proposalCalldata);
       

        if(proposal_execution_length == index){
        return();
        }

        QUEUED_TRANSACTIONS.write(action_hash, FALSE);
        CancelledAction.emit(action_hash, proposalTarget, proposalCalldata);
        cancelTransaction(_proposalId, index + 1, execution_time);
        return();
    }


    @external
    func queueTransaction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _proposalId : felt, index : felt, execution_time : felt
    ) {
        _onlyGovernance();
        let (time) = get_block_timestamp();
        let _delay : felt = DELAY.read(); 
        let delayedTime : felt = time + _delay;
        let is_on_time : felt = is_le(delayedTime, time);
        with_attr error_message("EXECUTION_TIME_UNDERESTIMATED") {
            assert is_on_time = TRUE;
        }
        let (governance) = GOVERNANCE_ADDRESS.read();
      
        let (proposal_execution_length) = IDolvenGovernance.returnExecutionLength(governance, _proposalId);
        let (proposalTarget) = IDolvenGovernance.returnProposalTarget(governance, _proposalId, index);
        let (proposalSelector) = IDolvenGovernance.returnProposalSelector(governance, _proposalId, index);
        let (proposalCalldata) = IDolvenGovernance.returnProposalCalldata(governance, _proposalId, index);

        //pedersen hash
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(execution_time, proposalTarget);
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, proposalSelector);
        let (action_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, proposalCalldata);
       

        if(proposal_execution_length == index){
        return();
        }

        QUEUED_TRANSACTIONS.write(action_hash, TRUE);
        QueuedAction.emit(action_hash, proposalTarget, proposalCalldata);
        queueTransaction(_proposalId, index + 1, execution_time);
        return();
    }

    @external
    func executeTransaction{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        _proposalId : felt, index : felt, execution_time : felt
    ){
        _onlyGovernance();

        let (governance) = GOVERNANCE_ADDRESS.read();
      
        let (proposal_execution_length) = IDolvenGovernance.returnExecutionLength(governance, _proposalId);
        let (proposalTarget) = IDolvenGovernance.returnProposalTarget(governance, _proposalId, index);
        let (proposalSelector) = IDolvenGovernance.returnProposalSelector(governance, _proposalId, index);
        let proposalCalldata : felt* = IDolvenGovernance.returnProposalCalldata(governance, _proposalId, index);

        //pedersen hash
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(execution_time, proposalTarget);
        let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, proposalSelector);
        let (action_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, proposalCalldata[0]);
        
        let (time) = get_block_timestamp();

        let is_queued : felt = QUEUED_TRANSACTIONS.read(action_hash);

        with_attr error_message("ACTION_NOT_QUEUED") {
            assert is_queued = TRUE;
        }

        let _gracePeriod : felt = GRACE_PERIOD.read();
        let graced_time : felt = _gracePeriod + time;
        let _is_before_grace_period : felt = is_le(time, graced_time);
        let is_after_execution_time : felt = is_le(execution_time, time); 
        with_attr error_message("GRACE_PERIOD_FINISHED") {
            assert _is_before_grace_period = TRUE;
        }

        with_attr error_message("TIMELOCK_NOT_FINISHED") {
            assert is_after_execution_time = TRUE;
        }

        if(proposal_execution_length == index){
        return();
        }

        let response = call_contract(
        contract_address=proposalTarget,
        function_selector=proposalSelector,
        calldata_size=1,
        calldata=proposalCalldata,
        );

        QUEUED_TRANSACTIONS.write(action_hash, FALSE);
        ExecutedAction.emit(action_hash, proposalTarget, proposalCalldata[0]);
        executeTransaction(_proposalId, index + 1, execution_time);
        return();
    }

    @external
    func changeDelay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        delay_duration: felt
    ) -> (delay_duration: felt) {
        _validateDelay(delay_duration);
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
    func changeVotingDuration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        voting_duration: felt
    ) -> (voting_duration: felt) {
        Ownable.assert_only_owner();
        VOTING_DURATION.write(voting_duration);
        return (voting_duration,);
    }

    // #Internal Functions

    // # Modifier
    func _validateDelay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
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

    @external
    func _onlyGovernance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) {
        let (msg_sender) = get_caller_address();
            with_attr error_message("ONLY_GOVERNANCE_CAN_EXECUTE") {
            assert_not_zero(msg_sender);
        }
        let (governance_address) = GOVERNANCE_ADDRESS.read();
           with_attr error_message("ONLY_GOVERNANCE_CAN_EXECUTE") {
            assert governance_address = msg_sender;
        }
        return();
    }
