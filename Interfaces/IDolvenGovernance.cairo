%lang starknet

from starkware.cairo.common.uint256 import Uint256

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

@contract_interface
namespace IDolvenGovernance {
    func returnProposalByNonce(proposalNonce: felt) -> (proposalDetails: Proposal) {
    }
    func returnExecutionLength(_proposalId: felt) -> (length: felt) {
    }
    func returnProposalTarget(_proposalId: felt, nonce : felt) -> (target: felt) {
    }
    func returnProposalSelector(_proposalId: felt, nonce : felt) -> (selector: felt) {
    }
    func returnProposalCalldata(_proposalId: felt, nonce : felt) -> (calldata: felt) {
    }
    func returnGovernanceStrategy() -> (strategyAddress: felt) {
    }
}
