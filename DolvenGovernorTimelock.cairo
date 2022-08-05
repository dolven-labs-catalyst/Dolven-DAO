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
from openzeppelin.security.safemath import SafeUint256
from starkware.cairo.common.math_cmp import is_le, is_not_zero, is_nn, is_in_range, is_nn_le
from openzeppelin.token.ERC20.interfaces.IERC20 import IERC20
from openzeppelin.access.ownable import Ownable
from openzeppelin.security.pausable import Pausable
from openzeppelin.security.reentrancy_guard import ReentrancyGuard
from Interfaces.IDolvenGovernance import IDolvenGovernance
# upper threhold of delay, in seconds
@storage_var
func MAXIMUM_DELAY() -> (res : felt):
end
# lower threshold of delay, in seconds
@storage_var
func MINUMUM_DELAY() -> (res : felt):
end

# Minimum time between queueing and execution of proposal
@storage_var
func DELAY() -> (res : felt):
end
# Delay before voting begin
@storage_var
func VOTING_DELAY() -> (res : felt):
end
# Time after delay while a proposal can be executed
@storage_var
func GRACE_PERIOD() -> (res : felt):
end
# Main Governance of Dolven Labs
@storage_var
func GOVERNANCE_ADDRESS() -> (res : felt):
end
# Total voting duration
@storage_var
func VOTING_DURATION() -> (res : felt):
end

# # Constructor
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    governance_address : felt,
    gracePeriod : felt,
    minumumDelay : felt,
    maximumDelay : felt,
    delay : felt,
    voting_delay : felt,
):
    alloc_locals
    let is_delay_shorter_than_max : felt = is_le(minumumDelay, delay)
    let is_delay_longer_than_max : felt = is_le(delay, maximumDelay)
    with_attr error_message("DELAY_SHORTER_THAN_MINIMUM"):
        assert is_delay_shorter_than_max = 1
    end
    with_attr error_message("DELAY_LONGER_THAN_MAXIMUM"):
        assert is_delay_longer_than_max = 1
    end
    let (deployer) = get_caller_address()
    Ownable.initializer(deployer)
    GRACE_PERIOD.write(gracePeriod)
    MINUMUM_DELAY.write(minumumDelay)
    MAXIMUM_DELAY.write(maximumDelay)
    DELAY.write(delay)
    VOTING_DELAY.write(voting_delay)
    GOVERNANCE_ADDRESS.write(governance_address)
    return ()
end

# #Viewers

@view
func getDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    delay : felt
):
    let delay : felt = DELAY.read()
    return (delay)
end

@view
func getGovernance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    address : felt
):
    let address : felt = GOVERNANCE_ADDRESS.read()
    return (address)
end

@view
func getVotingDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    delay : felt
):
    let voting_delay : felt = VOTING_DELAY.read()
    return (voting_delay)
end

@view
func getVotingDuration{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    delay : felt
):
    let voting_duration : felt = VOTING_DURATION.read()
    return (voting_duration)
end

@view
func isProposalOverGracePeriod{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    proposal_id : felt
) -> (status : felt):
    alloc_locals
    let _governanceAddress : felt = GOVERNANCE_ADDRESS.read()
    let (proposal_details) = IDolvenGovernance.returnProposalByNonce(
        _governanceAddress, proposal_id
    )
    let (time) = get_block_timestamp()
    let _gracePeriod : felt = GRACE_PERIOD.read()
    let condition : felt = _gracePeriod + proposal_details.executionTime
    let res : felt = is_nn_le(condition, time)
    return (res)
end

# #Externals

@external
func changeDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    delay_duration : felt
) -> (delay_duration : felt):
    check_duration(delay_duration)
    Ownable.assert_only_owner()
    DELAY.write(delay_duration)
    return (delay_duration)
end

@external
func changeVotingDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    voting_delay : felt
) -> (voting_delay : felt):
    Ownable.assert_only_owner()
    VOTING_DELAY.write(voting_delay)
    return (voting_delay)
end

@external
func changeGracePeriod{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    grace_time : felt
) -> (grace_time : felt):
    Ownable.assert_only_owner()
    GRACE_PERIOD.write(grace_time)
    return (grace_time)
end

@external
func changeVotingDuration{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    voting_duration : felt
) -> (voting_duration : felt):
    Ownable.assert_only_owner()
    VOTING_DURATION.write(voting_duration)
    return (voting_duration)
end

# #Internal Functions

# # Modifier
func check_duration{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    duration : felt
):
    alloc_locals
    let maximumDelay : felt = MAXIMUM_DELAY.read()
    let minumumDelay : felt = MINUMUM_DELAY.read()
    let is_delay_shorter_than_max : felt = is_le(minumumDelay, duration)
    let is_delay_longer_than_max : felt = is_le(duration, maximumDelay)
    with_attr error_message("DELAY_SHORTER_THAN_MINIMUM"):
        assert is_delay_shorter_than_max = 1
    end
    with_attr error_message("DELAY_LONGER_THAN_MAXIMUM"):
        assert is_delay_longer_than_max = 1
    end
    return ()
end
