// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract OmniParametricInsurance {
    enum PolicyStatus { Active, ClaimPending, Resolved, Canceled }

    struct Policy {
        address payable policyHolder;
        uint256 premiumPaidWei;
        uint256 coverageAmountWei;
        PolicyStatus status;
        bytes32 conditionsHash;
    }

    address payable public immutable hubAdmin;
    string public hubDescriptor;
    uint256 public platformFeeBps; // 250 = 2.5%
    uint256 public policyCounter;
    uint256 public accumulatedFees;
    bool public isHubHalted;

    mapping(address => bool) public authorizedOracles;
    mapping(uint256 => Policy) public policies;

    event OracleAdded(address indexed oracle);
    event PolicyPurchased(uint256 indexed policyId, address indexed holder, uint256 premium, uint256 coverage);
    event PolicyCanceled(uint256 indexed policyId, uint256 refundAmount);
    event TreasuryDeposited(address indexed funder, uint256 amount);
    event ReservesDrained(address indexed admin, uint256 amount);
    event ClaimFiled(uint256 indexed policyId);
    event FeesGathered(address indexed admin, uint256 amount);
    event HubHaltToggled(bool isHalted);
    event CoverageIncreased(uint256 indexed policyId, uint256 addedPremium);
    event ClaimResolved(uint256 indexed policyId, bool isApproved, uint256 payout);
    event OracleRevoked(address indexed oracle);
    event DescriptorUpdated(string newDescriptor);

    modifier onlyAdmin() {
        require(msg.sender == hubAdmin, "OmniInsurance: Access denied");
        _;
    }

    modifier whenNotHalted() {
        require(!isHubHalted, "OmniInsurance: Hub is halted");
        _;
    }

    constructor() {
        hubAdmin = payable(msg.sender);
        hubDescriptor = "Omni Base Parametric Insurance v1";
        platformFeeBps = 250; // 2.5%
        isHubHalted = false;
        authorizedOracles[msg.sender] = true;
    }

    // 1. addAuthorizedOracle
    function addAuthorizedOracle(address oracle) external onlyAdmin {
        require(!authorizedOracles[oracle], "OmniInsurance: Already authorized");
        authorizedOracles[oracle] = true;
        emit OracleAdded(oracle);
    }

    // 2. buyInsurancePolicy
    function buyInsurancePolicy(uint256 coverageAmountWei, bytes32 conditionsHash) external payable whenNotHalted returns (uint256) {
        require(msg.value > 0, "OmniInsurance: Zero premium");
        require(coverageAmountWei > msg.value, "OmniInsurance: Coverage too low");

        policyCounter++;
        policies[policyCounter] = Policy({
            policyHolder: payable(msg.sender),
            premiumPaidWei: msg.value,
            coverageAmountWei: coverageAmountWei,
            status: PolicyStatus.Active,
            conditionsHash: conditionsHash
        });

        emit PolicyPurchased(policyCounter, msg.sender, msg.value, coverageAmountWei);
        return policyCounter;
    }

    // 3. cancelActivePolicy
    function cancelActivePolicy(uint256 policyId) external {
        Policy storage p = policies[policyId];
        require(policyId > 0 && policyId <= policyCounter, "OmniInsurance: Invalid ID");
        require(msg.sender == p.policyHolder || msg.sender == hubAdmin, "OmniInsurance: Unauthorized");
        require(p.status == PolicyStatus.Active, "OmniInsurance: Cannot cancel now");

        p.status = PolicyStatus.Canceled;
        uint256 refund = p.premiumPaidWei;
        p.premiumPaidWei = 0;

        if (refund > 0) {
            (bool sent, ) = p.policyHolder.call{value: refund}("");
            require(sent, "OmniInsurance: Refund failed");
        }

        emit PolicyCanceled(policyId, refund);
    }

    // 4. depositPlatformTreasury
    function depositPlatformTreasury() external payable whenNotHalted {
        require(msg.value > 0, "OmniInsurance: Zero deposit");
        accumulatedFees += msg.value;
        emit TreasuryDeposited(msg.sender, msg.value);
    }

    // 5. drainHubReserves
    function drainHubReserves() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "OmniInsurance: Zero balance");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: balance}("");
        require(sent, "OmniInsurance: Sweep failed");

        emit ReservesDrained(hubAdmin, balance);
    }

    // 6. fileInsuranceClaim
    function fileInsuranceClaim(uint256 policyId) external whenNotHalted {
        Policy storage p = policies[policyId];
        require(policyId > 0 && policyId <= policyCounter, "OmniInsurance: Invalid ID");
        require(msg.sender == p.policyHolder, "OmniInsurance: Not the holder");
        require(p.status == PolicyStatus.Active, "OmniInsurance: Not active");

        p.status = PolicyStatus.ClaimPending;
        emit ClaimFiled(policyId);
    }

    // 7. gatherPlatformFees
    function gatherPlatformFees() external onlyAdmin {
        uint256 amount = accumulatedFees;
        require(amount > 0, "OmniInsurance: Zero fees");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: amount}("");
        require(sent, "OmniInsurance: Harvest failed");

        emit FeesGathered(hubAdmin, amount);
    }

    // 8. haltInsuranceHub
    function haltInsuranceHub(bool isHalted) external onlyAdmin {
        isHubHalted = isHalted;
        emit HubHaltToggled(isHalted);
    }

    // 9. increasePolicyCoverage
    function increasePolicyCoverage(uint256 policyId, uint256 addedCoverageWei) external payable whenNotHalted {
        Policy storage p = policies[policyId];
        require(policyId > 0 && policyId <= policyCounter, "OmniInsurance: Invalid ID");
        require(msg.sender == p.policyHolder, "OmniInsurance: Not the holder");
        require(p.status == PolicyStatus.Active, "OmniInsurance: Not active");
        require(msg.value > 0, "OmniInsurance: Zero premium added");

        p.premiumPaidWei += msg.value;
        p.coverageAmountWei += addedCoverageWei;

        emit CoverageIncreased(policyId, msg.value);
    }

    // 10. resolveClaimOutcome
    function resolveClaimOutcome(uint256 policyId, bool isApproved) external {
        Policy storage p = policies[policyId];
        require(policyId > 0 && policyId <= policyCounter, "OmniInsurance: Invalid ID");
        require(authorizedOracles[msg.sender] || msg.sender == hubAdmin, "OmniInsurance: Unauthorized oracle");
        require(p.status == PolicyStatus.ClaimPending, "OmniInsurance: No claim pending");

        p.status = PolicyStatus.Resolved;
        
        uint256 payout = 0;
        if (isApproved) {
            uint256 fee = (p.premiumPaidWei * platformFeeBps) / 10000;
            payout = p.premiumPaidWei - fee; // В реальном контракте выплата была бы из пула, здесь возвращаем заблокированную премию за вычетом комиссии платформы для симуляции
            accumulatedFees += fee;
        } else {
            accumulatedFees += p.premiumPaidWei; // Премия сгорает в пользу платформы
        }
        
        p.premiumPaidWei = 0;

        if (payout > 0) {
            (bool sent, ) = p.policyHolder.call{value: payout}("");
            require(sent, "OmniInsurance: Payout failed");
        }

        emit ClaimResolved(policyId, isApproved, payout);
    }

    // 11. revokeOracleAccess
    function revokeOracleAccess(address oracle) external onlyAdmin {
        require(authorizedOracles[oracle], "OmniInsurance: Not an oracle");
        require(oracle != msg.sender, "OmniInsurance: Cannot revoke self");
        authorizedOracles[oracle] = false;
        emit OracleRevoked(oracle);
    }

    // 12. updateHubDescriptor
    function updateHubDescriptor(string calldata newDescriptor) external onlyAdmin {
        require(bytes(newDescriptor).length > 0, "OmniInsurance: Empty string");
        hubDescriptor = newDescriptor;
        emit DescriptorUpdated(newDescriptor);
    }
}