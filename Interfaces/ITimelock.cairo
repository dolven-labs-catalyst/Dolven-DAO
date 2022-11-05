%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace ITimelockController {
    func getDelay() -> (delay: felt) {
    }
    func getVotingDuration() -> (delay: felt) {
    }
    func getVotingDelay() -> (delay: felt) {
    }
    func isActionQueued(action_hash : felt) -> (res: felt) {
    }
    func executeTransaction(prop_id : felt, index : felt) -> (res: felt) {
    }
    func cancelTransaction(prop_id : felt, index : felt, execution_time : felt) -> (res: felt) {
    }
    func isProposalPassed(governance: felt, prop_id : felt) -> (res: felt) {
    }
    func getVotingPower(strategy: felt, user_account : felt) -> (Uint256: felt) {
    }
    func isProposalOverGracePeriod(proposal_id: felt) -> (status: felt) {
    }
}
