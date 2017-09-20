pragma solidity ^0.4.14;

import "SafeMath.sol";
import "OfferingLibrary.sol";

library AuctionOfferingLibrary {
    using SafeMath for uint;
    using OfferingLibrary for OfferingLibrary.Offering;

    struct AuctionOffering {
        uint  endTime;
        uint  extensionDuration;
        uint  minBidIncrease;
        address winningBidder;
        uint bidCount;
        mapping(address => uint) pendingReturns;
    }

    function construct(
        AuctionOffering storage self,
        uint _endTime,
        uint _extensionDuration,
        uint _minBidIncrease
    ) {
        require(_endTime > now);
        self.endTime = _endTime;
        self.extensionDuration = _extensionDuration;
        require(_minBidIncrease > 0);
        self.minBidIncrease = _minBidIncrease;
    }

    function bid(
        AuctionOffering storage self,
        OfferingLibrary.Offering storage offering
    ) {
        require(now < self.endTime);
        require(msg.sender != self.winningBidder);
        require(offering.isContractNodeOwner());

        uint bidValue = self.pendingReturns[msg.sender].add(msg.value);
        self.pendingReturns[msg.sender] = 0;

        if (self.winningBidder == 0x0) {
            require(bidValue >= offering.price);
        } else {
            require(bidValue >= offering.price.add(self.minBidIncrease));
            self.pendingReturns[self.winningBidder] = self.pendingReturns[self.winningBidder].add(offering.price);
        }

        self.winningBidder = msg.sender;
        self.bidCount += 1;
        offering.price = bidValue;

        if ((self.endTime - self.extensionDuration) <= now) {
            self.endTime = now.add(self.extensionDuration);
        }

        var extraEventData = new uint[](3);
        extraEventData[0] = uint(msg.sender);
        extraEventData[1] = offering.price;
        extraEventData[2] = now;
        offering.fireOnChanged("bid", extraEventData);
    }

    function withdraw(
        AuctionOffering storage self,
        OfferingLibrary.Offering storage offering,
        address _address
    ) {
        require(msg.sender == _address || offering.isSenderEmergencyMultisig());
        var pendingReturns = self.pendingReturns[_address];
        if (pendingReturns > 0) {
            self.pendingReturns[_address] = 0;
            _address.transfer(pendingReturns);
            offering.fireOnChanged("withdraw");
        }
    }

    function finalize(
        AuctionOffering storage self,
        OfferingLibrary.Offering storage offering,
        bool transferPrice
    ) {
        require(now > self.endTime);
        require(self.winningBidder != 0x0);
        offering.transferOwnership(self.winningBidder, offering.price);

        if (transferPrice) {
            offering.originalOwner.transfer(offering.price);
        } else {
            self.pendingReturns[offering.originalOwner] =
                self.pendingReturns[offering.originalOwner].add(offering.price);
        }
    }

    function reclaimOwnership(
        AuctionOffering storage self,
        OfferingLibrary.Offering storage offering
    ) {
        if (offering.isSenderEmergencyMultisig()) {
            if (!hasNoBids(self) && !offering.wasEmergencyCancelled()) {
                self.pendingReturns[self.winningBidder] = offering.price;
            }
        } else {
            require(hasNoBids(self));
        }
        offering.reclaimOwnership();
    }

    function setSettings(
        AuctionOffering storage self,
        OfferingLibrary.Offering storage offering,
        uint _startPrice,
        uint _endTime,
        uint _extensionDuration,
        uint _minBidIncrease
    ) {
        require(offering.isSenderOriginalOwner());
        require(hasNoBids(self));
        offering.price = _startPrice;

        construct(
            self,
            _endTime,
            _extensionDuration,
            _minBidIncrease
        );
        offering.fireOnChanged("setSettings");
    }

    function hasNoBids(AuctionOffering storage self) returns(bool) {
        return self.winningBidder == 0x0;
    }

    function pendingReturns(AuctionOffering storage self, address bidder) returns (uint) {
        return self.pendingReturns[bidder];
    }
}

