contract owned {
    address public owner;

    function owned() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        if (msg.sender != owner) throw;
        _
    }

    function transferOwnership(address newOwner) onlyOwner {
        owner = newOwner;
    }
}


contract DAO is owned {

    /* Contract Variables and events */
    uint public minimumQuorum;
    uint public debatingPeriodInMinutes;
    int public majorityMargin;
    Proposal[] public proposals;
    uint public numProposals;
    mapping (address => uint) public memberId;
    Member[] public members;

    event ProposalAdded(uint proposalID, address recipient, uint amount, string description);
    event Voted(uint proposalID, bool position, address voter, string justification);
    event ProposalTallied(uint proposalID, int result, uint quorum, bool active);
    event MembershipChanged(address member, bool isMember);
    event ChangeOfRules(uint minimumQuorum, uint debatingPeriodInMinutes, int majorityMargin);

    struct Proposal {
        address recipient;
        uint amount;
        string description;
        uint votingDeadline;
        bool executed;
        bool proposalPassed;
        uint numberOfVotes;
        int currentResult;
        bytes32 proposalHash;
        Vote[] votes;
        mapping (address => bool) voted;
    }

    struct Member {
        address member;
        bool canVote;
        string name;
        uint memberSince;
    }

    struct Vote {
        bool inSupport;
        address voter;
        string justification;
    }

    /* modifier that allows only shareholders to vote and create new proposals */
    modifier onlyMembers {
        if (memberId[msg.sender] == 0
        || !members[memberId[msg.sender]].canVote)
        throw;
        _
    }

    /* First time setup */
    function DAO(
        uint minimumQuorumForProposals,
        uint minutesForDebate,
        int marginOfVotesForMajority, address congressLeader
    ) {
        changeVotingRules(minimumQuorumForProposals, minutesForDebate, marginOfVotesForMajority);
        members.length++;
        members[0] = Member({member: 0, canVote: false, memberSince: now, name: ''});
        if (congressLeader != 0) owner = congressLeader;
    }

    /*make member*/
    function changeMembership(address targetMember, bool canVote, string memberName) onlyOwner {
        uint id;
        if (memberId[targetMember] == 0) {
           memberId[targetMember] = members.length;
           id = members.length++;
           members[id] = Member({member: targetMember, canVote: canVote, memberSince: now, name: memberName});
        } else {
            id = memberId[targetMember];
            Member m = members[id];
            m.canVote = canVote;
        }

        MembershipChanged(targetMember, canVote);
    }

    /*change rules*/
    function changeVotingRules(
        uint minimumQuorumForProposals,
        uint minutesForDebate,
        int marginOfVotesForMajority
    ) onlyOwner {
        minimumQuorum = minimumQuorumForProposals;
        debatingPeriodInMinutes = minutesForDebate;
        majorityMargin = marginOfVotesForMajority;

        ChangeOfRules(minimumQuorum, debatingPeriodInMinutes, majorityMargin);
    }

    /* Function to create a new proposal */
    function newProposal(
        address beneficiary,
        uint etherAmount,
        string JobDescription,
        bytes transactionBytecode
    )
        onlyMembers
        returns (uint proposalID)
    {
        proposalID = proposals.length++;
        Proposal p = proposals[proposalID];
        p.recipient = beneficiary;
        p.amount = etherAmount;
        p.description = JobDescription;
        p.proposalHash = sha3(beneficiary, etherAmount, transactionBytecode);
        p.votingDeadline = now + debatingPeriodInMinutes * 1 minutes;
        p.executed = false;
        p.proposalPassed = false;
        p.numberOfVotes = 0;
        ProposalAdded(proposalID, beneficiary, etherAmount, JobDescription);
        numProposals = proposalID+1;
    }

    /* function to check if a proposal code matches */
    function checkProposalCode(
        uint proposalNumber,
        address beneficiary,
        uint etherAmount,
        bytes transactionBytecode
    )
        constant
        returns (bool codeChecksOut)
    {
        Proposal p = proposals[proposalNumber];
        return p.proposalHash == sha3(beneficiary, etherAmount, transactionBytecode);
    }

    function vote(
        uint proposalNumber,
        bool supportsProposal,
        string justificationText
    )
        onlyMembers
        returns (uint voteID)
    {
        Proposal p = proposals[proposalNumber];         // Get the proposal
        if (p.voted[msg.sender] == true) throw;         // If has already voted, cancel
        p.voted[msg.sender] = true;                     // Set this voter as having voted
        p.numberOfVotes++;                              // Increase the number of votes
        if (supportsProposal) {                         // If they support the proposal
            p.currentResult++;                          // Increase score
        } else {                                        // If they don't
            p.currentResult--;                          // Decrease the score
        }
        // Create a log of this event
        Voted(proposalNumber,  supportsProposal, msg.sender, justificationText);
    }

    function executeProposal(uint proposalNumber, bytes transactionBytecode) returns (int result) {
        Proposal p = proposals[proposalNumber];
        /* Check if the proposal can be executed */
        if (now < p.votingDeadline                                                  // has the voting deadline arrived?
            || p.executed                                                           // has it been already executed?
            || p.proposalHash != sha3(p.recipient, p.amount, transactionBytecode)   // Does the transaction code match the proposal?
            || p.numberOfVotes < minimumQuorum)                                    // has minimum quorum?
            throw;

        /* execute result */
        if (p.currentResult > majorityMargin) {
            /* If difference between support and opposition is larger than margin */
            p.recipient.call.value(p.amount * 1 ether)(transactionBytecode);
            p.executed = true;
            p.proposalPassed = true;
        } else {
            p.executed = true;
            p.proposalPassed = false;
        }
        // Fire Events
        ProposalTallied(proposalNumber, p.currentResult, p.numberOfVotes, p.proposalPassed);
    }
}
