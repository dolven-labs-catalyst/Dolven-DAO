%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from contracts.DAO.DolvenGovernorTimelock import initializer
from contracts.DAO.DolvenProposalValidator import initializer_validator

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _PROPOSITION_THRESHOLD: Uint256,
    _VOTING_DURATION: felt,
    _VOTE_DIFFERENTIAL: Uint256,
    _MINIMUM_QUORUM: Uint256,
    _VOTING_TYPE: felt,
    governance_address: felt,
    gracePeriod: felt,
    minumumDelay: felt,
    maximumDelay: felt,
    delay: felt,
    voting_delay: felt,
    _deployer : felt
) {
    initializer_validator(_PROPOSITION_THRESHOLD, _VOTING_DURATION, _VOTE_DIFFERENTIAL, _MINIMUM_QUORUM, _VOTING_TYPE, _deployer);
    initializer(governance_address, gracePeriod, minumumDelay, maximumDelay, delay, voting_delay, _deployer);
    return ();
}
