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
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math_cmp import is_le, is_not_zero, is_nn, is_nn_le, is_in_range
from contracts.openzeppelin.token.ERC20.interfaces.IERC20 import IERC20
from contracts.openzeppelin.access.ownable import Ownable
from contracts.openzeppelin.security.pausable import Pausable
from contracts.openzeppelin.security.reentrancy_guard import ReentrancyGuard
from contracts.Libraries.DolvenApprover import DolvenApprover
from contracts.Interfaces.ITimelock import ITimelockController
from contracts.Interfaces.IDolvenVault import IDolvenVault
from starkware.cairo.common.hash import hash2

// # Storages

// Status of proposal
const CANCELLED = 0;
const SUCCESS = 1;
const PENDING = 2;
const QUEUED = 3;
const ACTIVE = 4;
const EXECUTED = 5;
const FAILED = 6;
const EXPIRED = 7;

const NAME = 8749144107276083488161720003882106979964465;  // dolvenGovernanceV1 - felt - 0x646f6c76656e476f7665726e616e63655631 hex

@storage_var
func governanceStrategy() -> (res: felt) {
}

@storage_var
func _votingDelay() -> (res: felt) {
}

@storage_var
func timeLocker() -> (res: felt) {
}

@storage_var
func proposalNonce() -> (res: felt) {
}

// #Structs
struct Proposal {
    id: felt,
    executor: felt,
    execute_param_len : felt,
    creator: felt,
    proposalType: felt,
    startTimestamp: felt,
    endTimestamp: felt,
    executionTime: felt,
    forVotes: Uint256,
    againstVotes: Uint256,
    isExecuted: felt,
    isCancelled: felt,
    strategy: felt,
}



struct Vote {
    voteFrom: felt,
    voteProposalNonce: felt,
    voteResult: felt,
    votingPower: Uint256,
}

// # Mappings

@storage_var
func proposals(nonce: felt) -> (res: Proposal) {
}

@storage_var
func proposal_execution_len(proposal_id: felt) -> (len: felt) {
}

@storage_var
func proposal_targets(proposal_id: felt, nonce : felt) -> (res: felt) {
}

@storage_var
func proposal_selectors(proposal_id: felt, nonce : felt) -> (res: felt) {
}

@storage_var
func proposal_calldatas(proposal_id: felt, nonce : felt) -> (res: felt) {
}

@storage_var
func proposalCount(proposalId: felt) -> (voteIndexCount: felt) {
}

@storage_var
func proposalsVotes(nonce: felt, voteIndex: felt) -> (res: Vote) {
}

@storage_var
func userNonce(user_account: felt) -> (res: felt) {
}

@storage_var
func _authorizedExecutors(executor: felt) -> (res: felt) {
}

@storage_var
func userVotes(user_address: felt, voteIndex: felt) -> (res: Vote) {
}

@storage_var
func userVotesForProposal(user_address: felt, proposalId: felt) -> (res: Vote) {
}

// # Events

@event
func VoteEmitted(proposalId: felt, voter: felt, support: felt, votingPower: Uint256) {
}

@event
func ProposalQueued(proposalId: felt, executionTime: felt, user: felt) {
}

@event
func ProposalExecuted(proposalId: felt) {
}

@event
func ProposalCancelled(proposalId: felt) {
}

@event
func ProposalCreated(
    proposalId: felt,
    creator: felt,
    startTimestamp: felt,
    endTimestamp: felt,
    strategy: felt,
) {
}

// # Constructor

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _governanceStrategy: felt,
    __votingDelay: felt,
    executor: felt,
    firstSignerAddress: felt,
    secondSignerAddress: felt,
    initialApprover: felt,
) {
    governanceStrategy.write(_governanceStrategy);
    timeLocker.write(executor);
    _votingDelay.write(__votingDelay);
    DolvenApprover.initializer(firstSignerAddress, secondSignerAddress, initialApprover);
    return ();
}

// # Viewers

@view
func getProposalState{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proposal_id: felt
) -> (state: felt) {
    alloc_locals;
    let proposal_count: felt = proposalNonce.read();
    with_attr error_message("DolvenGovernance::getProposalState INVALID_PROPOSAL_ID") {
        assert_nn_le(proposal_id, proposal_count);
    }
    let proposal_details: Proposal = proposals.read(proposal_id);
    let (time) = get_block_timestamp();
    let (this) = get_contract_address();
    let is_time_less_than_starttps: felt = is_le(time, proposal_details.startTimestamp);
    let is_time_less_than_endtps: felt = is_le(time, proposal_details.endTimestamp);
    let is_proposal_passed: felt = ITimelockController.isProposalPassed(
        proposal_details.executor, this, proposal_details.id
    );
    let is_proposal_over_grace_period: felt = ITimelockController.isProposalOverGracePeriod(
        this, proposal_details.id
    );
    if (proposal_details.isCancelled == TRUE) {
        return (CANCELLED,);
    } else {
        if (is_time_less_than_starttps == 1) {
            return (PENDING,);
        } else {
            if (is_time_less_than_endtps == 1) {
                return (ACTIVE,);
            } else {
                if (is_proposal_passed == 0) {
                    return (FAILED,);
                } else {
                    if (proposal_details.executionTime == 0) {
                        return (SUCCESS,);
                    } else {
                        if (proposal_details.isExecuted == 1) {
                            return (EXECUTED,);
                        } else {
                            if (is_proposal_over_grace_period == 1) {
                                return (EXPIRED,);
                            } else {
                                return (QUEUED,);
                            }
                        }
                    }
                }
            }
        }
    }
}

@view
func returnGovernanceStrategy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> (strategyAddress: felt) {
    let strategy: felt = governanceStrategy.read();
    return (strategy,);
}

@view
func returnTimelocker{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    timeLocker: felt
) {
    let executor: felt = timeLocker.read();
    return (executor,);
}

@view
func returnproposalNonce{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    proposalNonce: felt
) {
    let nonce: felt = proposalNonce.read();
    return (nonce,);
}

@view
func returnProposalByNonce{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proposalNonce: felt
) -> (proposalDetails: Proposal) {
    let proposal: Proposal = proposals.read(proposalNonce);
    return (proposal,);
}

@view
func returnVoteCountByProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proposalId: felt
) -> (voteCount: felt) {
    let proposalVoteCount: felt = proposalCount.read(proposalId);
    return (proposalVoteCount,);
}

@view
func returnUserVoteCount{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_account: felt
) -> (voteCount: felt) {
    let vote_count: felt = userNonce.read(user_account);
    return (vote_count,);
}

@view
func returnUserVoteByProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_account: felt, proposal_id: felt
) -> (voteDetail: Vote) {
    let vote_details: Vote = userVotesForProposal.read(user_account, proposal_id);
    return (vote_details,);
}

@view
func getProposals{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    proposals_len: felt, proposals: Proposal*
) {
    let (proposals_len, proposals) = recursiveGetProposals(0);
    return (proposals_len, proposals - proposals_len * Proposal.SIZE);
}

@view
func getVotesByProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proposal_id: felt
) -> (votes_len: felt, votes: Vote*) {
    let (votes_len, votes) = recursiveGetVotes(proposal_id, 0);
    return (votes_len, votes - votes_len * Vote.SIZE);
}

@view
func getVotesByUser{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_account: felt
) -> (user_vote_len: felt, user_vote: Vote*) {
    let (user_votes_len, user_votes) = recursiveGetUserVotes(user_account, 0);
    return (user_votes_len, user_votes - user_votes_len * Vote.SIZE);
}

// #recursive functions

func recursiveGetProposals{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proposal_nonce: felt
) -> (proposals_len: felt, proposals: Proposal*) {
    alloc_locals;
    let proposal_count: felt = proposalNonce.read();
    let (_proposalDetails: Proposal) = proposals.read(proposal_nonce);
    if (proposal_count == proposal_nonce) {
        let (found_proposals: Proposal*) = alloc();
        return (0, found_proposals);
    }

    let (proposal_memory_location_len, proposal_memory_location: Proposal*) = recursiveGetProposals(
        proposal_nonce + 1
    );
    assert [proposal_memory_location] = _proposalDetails;
    return (proposal_memory_location_len + 1, proposal_memory_location + Proposal.SIZE);
}

func recursiveGetVotes{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proposal_id: felt, vote_index: felt
) -> (votes_len: felt, votes: Vote*) {
    alloc_locals;
    let proposal_vote_count: felt = proposalCount.read(proposal_id);
    let (_voteDetails: Vote) = proposalsVotes.read(proposal_id, vote_index);
    if (proposal_vote_count == vote_index) {
        let (found_votes: Vote*) = alloc();
        return (0, found_votes);
    }

    let (vote_memory_location_len, vote_memory_location: Vote*) = recursiveGetVotes(
        proposal_id, vote_index + 1
    );
    assert [vote_memory_location] = _voteDetails;
    return (vote_memory_location_len + 1, vote_memory_location + Vote.SIZE);
}

func recursiveGetUserVotes{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    account_address: felt, vote_index: felt
) -> (votes_len: felt, votes: Vote*) {
    alloc_locals;
    let user_vote_count: felt = userNonce.read(account_address);
    let (_voteDetails: Vote) = userVotes.read(account_address, vote_index);
    if (user_vote_count == vote_index) {
        let (found_votes: Vote*) = alloc();
        return (0, found_votes);
    }

    let (vote_memory_location_len, vote_memory_location: Vote*) = recursiveGetUserVotes(
        account_address, vote_index + 1
    );
    assert [vote_memory_location] = _voteDetails;
    return (vote_memory_location_len + 1, vote_memory_location + Vote.SIZE);
}

// # External Functions

@external
func createProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _executor: felt, targets_len : felt, targets : felt*, selector_len : felt, selector : felt*,  calldatas_len : felt, calldatas : felt*, _ipfsHash: felt, _proposalType: felt
) -> (res: felt) {
    alloc_locals;
    ReentrancyGuard._start();
    DolvenApprover.onlyApprover();
    let (msg_sender) = get_caller_address();
    let (current_time) = get_block_timestamp();
    let governanceStrategy_address: felt = governanceStrategy.read();
    let isExecutorAuthorized : felt = _authorizedExecutors.read(_executor);

    let is_proposal_valid : felt = is_nn_le(0, _proposalType);

    with_attr error_message("DolvenGovernance::createProposal INVALID_PROPOSAL_TYPE") {
        assert is_proposal_valid = TRUE;
    }
    with_attr error_message("DolvenGovernance::createProposal INCONSISTENT_PARAMS_LENGTH") {
        assert targets_len = selector_len;
    }
    
    with_attr error_message("DolvenGovernance::createProposal INCONSISTENT_PARAMS_LENGTH") {
        assert calldatas_len = targets_len;
    }

    with_attr error_message("DolvenGovernance::createProposal EXECUTOR_NOT_AUTHORIZED") {
        assert isExecutorAuthorized = TRUE;
    }

    let VOTING_DELAY: felt = _votingDelay.read();
    let VOTING_DURATION: felt = ITimelockController.getVotingDuration(_executor);
    let proposalStartTime: felt = current_time + VOTING_DELAY;
    let proposalEndTime: felt = proposalStartTime + VOTING_DURATION;

    let nonce: felt = proposalNonce.read();
    let zero_as_uint256: Uint256 = Uint256(0, 0);

    let new_proposal: Proposal = Proposal(
        id=nonce,
        executor=_executor,
        execute_param_len=targets_len, 
        creator=msg_sender,
        proposalType=_proposalType,
        startTimestamp=proposalStartTime,
        endTimestamp=proposalEndTime,
        executionTime=0,
        forVotes=zero_as_uint256,
        againstVotes=zero_as_uint256,
        isExecuted=FALSE,
        isCancelled=FALSE,
        strategy=governanceStrategy_address,
    );
    proposals.write(nonce, new_proposal);
    processCalldata(nonce, 0, calldatas_len, calldatas, selector_len, selector, targets_len, targets);

    ProposalCreated.emit(
        proposalId=nonce,
        creator=msg_sender,
        startTimestamp=proposalStartTime,
        endTimestamp=proposalEndTime,
        strategy=governanceStrategy_address,
    );
    proposalNonce.write(nonce + 1);
    ReentrancyGuard._end();

    return (nonce,);
}

@external
func cancelProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _proposalId: felt
) {
    alloc_locals;
    ReentrancyGuard._start();
    DolvenApprover.onlyApprover();
    let state: felt = getProposalState(_proposalId);
    with_attr error_message("DolvenGovernance::cancelProposal ONLY_BEFORE_EXECUTED") {
        assert_not_equal(state, EXECUTED);
        assert_not_equal(state, CANCELLED);
        assert_not_equal(state, EXPIRED);
    }
    let proposalDetails: Proposal = proposals.read(_proposalId);

    let new_proposal: Proposal = Proposal(
        id=proposalDetails.id,
        executor=proposalDetails.executor,
        execute_param_len=proposalDetails.execute_param_len,
        creator=proposalDetails.creator,
        proposalType=proposalDetails.proposalType,
        startTimestamp=proposalDetails.startTimestamp,
        endTimestamp=proposalDetails.endTimestamp,
        executionTime=proposalDetails.executionTime,
        forVotes=proposalDetails.forVotes,
        againstVotes=proposalDetails.againstVotes,
        isExecuted=proposalDetails.isExecuted,
        isCancelled=TRUE,
        strategy=proposalDetails.strategy,
    );

    proposals.write(proposalDetails.id, new_proposal);
    ITimelockController.cancelTransaction(proposalDetails.executor, proposalDetails.id, 0);
    
    ProposalCancelled.emit(proposalId=proposalDetails.id);
    ReentrancyGuard._end();

    return ();
}

@external
func queueProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _proposalId: felt
) {
    alloc_locals;
    ReentrancyGuard._start();
    DolvenApprover.onlyApprover();
    let state: felt = getProposalState(_proposalId);
    with_attr error_message("DolvenGovernance::queueProposal INVALID_STATE_FOR_QUEUE") {
        assert state = SUCCESS;
    }
    let (msg_sender) = get_caller_address();
    let proposalDetails: Proposal = proposals.read(_proposalId);
    let (current_time) = get_block_timestamp();
    let queueDelay: felt = ITimelockController.getDelay(proposalDetails.executor);
    let _executionTime: felt = current_time + queueDelay;
    
    _queueOrRevert(proposalDetails.executor, 0, proposalDetails.id, _executionTime, proposalDetails.execute_param_len);
    let new_proposal: Proposal = Proposal(
        id=proposalDetails.id,
        executor=proposalDetails.executor,
        execute_param_len=proposalDetails.execute_param_len,
        creator=proposalDetails.creator,
        proposalType=proposalDetails.proposalType,
        startTimestamp=proposalDetails.startTimestamp,
        endTimestamp=proposalDetails.endTimestamp,
        executionTime=_executionTime,
        forVotes=proposalDetails.forVotes,
        againstVotes=proposalDetails.againstVotes,
        isExecuted=proposalDetails.isExecuted,
        isCancelled=proposalDetails.isCancelled,
        strategy=proposalDetails.strategy,
    );
    proposals.write(proposalDetails.id, new_proposal);

    ProposalQueued.emit(
        proposalId=proposalDetails.id, executionTime=_executionTime, user=msg_sender
    );
    ReentrancyGuard._end();

    return ();
}

@external
func executeProposal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _proposalId: felt
) {
    ReentrancyGuard._start();
    DolvenApprover.onlyApprover();
    let state: felt = getProposalState(_proposalId);
    with_attr error_message("DolvenGovernance::queueProposal ONLY_QUEUED_PROPOSALS") {
        assert state = QUEUED;
    }
    let (_executionTime) = get_block_timestamp();
    let (msg_sender) = get_caller_address();
    let proposalDetails: Proposal = proposals.read(_proposalId);

    ITimelockController.executeTransaction(proposalDetails.executor, proposalDetails.execute_param_len, 0);

    let new_proposal : Proposal = Proposal(
        id=proposalDetails.id,
        executor=proposalDetails.executor,
        execute_param_len=proposalDetails.execute_param_len,
        creator=proposalDetails.creator,
        proposalType=proposalDetails.proposalType,
        startTimestamp=proposalDetails.startTimestamp,
        endTimestamp=proposalDetails.endTimestamp,
        executionTime=proposalDetails.executionTime,
        forVotes=proposalDetails.forVotes,
        againstVotes=proposalDetails.againstVotes,
        isExecuted=TRUE,
        isCancelled=proposalDetails.isCancelled,
        strategy=proposalDetails.strategy,
    );
    proposals.write(proposalDetails.id, new_proposal);

    ProposalExecuted.emit(proposalId=proposalDetails.id);
    ReentrancyGuard._end();

    return ();
}

@external
func submitVote{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    proposalId: felt, support: felt
) {
    let (msg_sender) = get_caller_address();
    _submitVote(msg_sender, proposalId, support);
    return ();
}

@external
func submitVoteBySignature{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*
}(proposalId: felt, support: felt, sig: (felt, felt)) {
    alloc_locals;
    let (msg_sender) = get_caller_address();
    let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(proposalId, support);
    let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, NAME);

    // reverts, if cannot resolve the signature see: https://www.cairo-lang.org/docs/hello_starknet/signature_verification.html
    verify_ecdsa_signature(
        message=basic_hash, public_key=msg_sender, signature_r=sig[0], signature_s=sig[1]
    );

    _submitVote(msg_sender, proposalId, support);

    return ();
}

// # Internal Functions

func _queueOrRevert{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_executor : felt, index : felt, proposal_nonce : felt, executionTime : felt, loop_size : felt){
    let _proposal_calldata : felt = proposal_calldatas.read(proposal_nonce, index);
    let _proposal_target : felt = proposal_targets.read(proposal_nonce, index);
    let _proposal_select : felt = proposal_selectors.read(proposal_nonce, index);

    let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(executionTime, _proposal_target);
    let (basic_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, _proposal_select);
    let (action_hash) = hash2{hash_ptr=pedersen_ptr}(basic_hash, _proposal_calldata);

    if (index == loop_size){
    return();
    }

    ITimelockController.isActionQueued(_executor, action_hash);
    _queueOrRevert(_executor, index + 1, proposal_nonce, executionTime, loop_size);
    return();

}

func processCalldata{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_nonce : felt, index : felt, _calldata_len : felt, _calldata : felt* , _selector_len : felt, _selector : felt*, _targets_len : felt, _targets : felt*){
    
    proposal_calldatas.write(_nonce, index, [_calldata]);
    proposal_selectors.write(_nonce, index, [_selector]);
    proposal_targets.write(_nonce, index, [_targets]);
    
    if (_calldata_len == index){
    return();
    }
  

    processCalldata(_nonce, index + 1, _calldata_len, _calldata + 1, _targets_len, _targets + 1, _selector_len, _selector + 1, );
    return();

}


func _submitVote{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    voter: felt, proposalId: felt, support: felt
) {
    alloc_locals;
    ReentrancyGuard._start();
    let state: felt = getProposalState(proposalId);
    with_attr error_message("DolvenGovernance::_submitVote VOTING_CLOSED") {
        assert state = ACTIVE;
    }
    let proposalDetails: Proposal = proposals.read(proposalId);
    let user_vote: Vote = userVotesForProposal.read(voter, proposalId);
    let zero_as_uint256: Uint256 = Uint256(0, 0);

    with_attr error_message("DolvenGovernance::_submitVote VOTE_ALREADY_SUBMITTED") {
        assert user_vote.votingPower = zero_as_uint256;
    }
    let _forVotes: Uint256 = proposalDetails.forVotes;
    let _againstVotes: Uint256 = proposalDetails.againstVotes;
    let _votingPower: Uint256 = IDolvenVault.get_userTicketCount(
        proposalDetails.executor, proposalDetails.strategy, voter
    );

    let _user_nonce: felt = userNonce.read(voter);
    let total_voteCount: felt = proposalCount.read(proposalId);

    let new_voteDetails: Vote = Vote(
        voteFrom=voter,
        voteProposalNonce=proposalDetails.id,
        voteResult=support,
        votingPower=_votingPower,
    );

    if (support == TRUE) {
        let _forVotes: Uint256 = SafeUint256.add(_forVotes, _votingPower);
        let new_proposalDetails: Proposal = Proposal(
            id=proposalDetails.id,
            executor=proposalDetails.executor,
            execute_param_len=proposalDetails.execute_param_len,
            creator=proposalDetails.creator,
            proposalType=proposalDetails.proposalType,
            startTimestamp=proposalDetails.startTimestamp,
            endTimestamp=proposalDetails.endTimestamp,
            executionTime=proposalDetails.executionTime,
            forVotes=_forVotes,
            againstVotes=proposalDetails.againstVotes,
            isExecuted=proposalDetails.isExecuted,
            isCancelled=proposalDetails.isCancelled,
            strategy=proposalDetails.strategy,
        );
    } else {
        let _againstVotes: Uint256 = SafeUint256.add(_againstVotes, _votingPower);
        let new_proposalDetails: Proposal = Proposal(
            id=proposalDetails.id,
            executor=proposalDetails.executor,
            execute_param_len=proposalDetails.execute_param_len,
            creator=proposalDetails.creator,
            proposalType=proposalDetails.proposalType,
            startTimestamp=proposalDetails.startTimestamp,
            endTimestamp=proposalDetails.endTimestamp,
            executionTime=proposalDetails.executionTime,
            forVotes=proposalDetails.forVotes,
            againstVotes=_againstVotes,
            isExecuted=proposalDetails.isExecuted,
            isCancelled=proposalDetails.isCancelled,
            strategy=proposalDetails.strategy,
        );
    }

    userVotes.write(voter, _user_nonce, new_voteDetails);
    userVotesForProposal.write(voter, proposalDetails.id, new_voteDetails);
    proposalsVotes.write(proposalDetails.id, total_voteCount, new_voteDetails);
    proposalCount.write(proposalDetails.id, total_voteCount + 1);
    userNonce.write(voter, _user_nonce + 1);

    VoteEmitted.emit(
        proposalId=proposalDetails.id,
        voter=voter,
        support=support,
        votingPower=_votingPower,
    );
    ReentrancyGuard._end();
    return ();
}

func _authorizeExecutor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_executor: felt) {
    _authorizedExecutors.write(_executor, TRUE);
    return ();
}

func _unauthorizeExecutor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_executor: felt) {
    _authorizedExecutors.write(_executor, FALSE);
    return ();
}

// Setters
@external
func setVotingDelay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(__votingDelay : felt){
    DolvenApprover.onlyApprover();
    _votingDelay.write(__votingDelay);
    return();
}

@external
func setGovernanceStrategy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_strategy : felt){
    DolvenApprover.onlyApprover();
    governanceStrategy.write(_strategy);
    return();
}

@external
func setDolvenExecutor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    executor: felt
) {
    DolvenApprover.onlyApprover();
    timeLocker.write(executor);
    return ();
}


@external
func unauthorizeExecutor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(executor : felt){
    DolvenApprover.onlyApprover();
    _authorizedExecutors.write(executor, FALSE);
    return();
}

@external
func authorizeExecutor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(executor : felt){
    DolvenApprover.onlyApprover();
    _authorizedExecutors.write(executor, TRUE);
    return();
}

