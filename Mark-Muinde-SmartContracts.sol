// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract P2P {

    //Struct for Prosumers
    struct Prosumer {
        address id;
        int energyStatus;
        uint balance;
    }
    
    //mapping for prosumer account storage using a prosumer's address as the key
    mapping(address => Prosumer) public prosumers;


    //public function to register prosumer
    function registerProsumer() public virtual {
        Prosumer memory newProsumer = Prosumer(msg.sender, 0, 0);
        prosumers[msg.sender] = newProsumer;
    }

    //internal function to get absolute value since Solidity doesn't have inbuilt math library
    function abs(int256 x) internal pure returns (uint256) {
        if (x < 0) {
            return uint256(-x);
        }
        return uint256(x);
    }

    //internal function to get minimum value since Solidity doesn't have inbuilt math library
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    //IMPROVEMENT:
    //addresses (queues) for buyers and sellers so that matching equal energy buying and selling requests is easier
    address[] internal  sellers;
    address[] internal buyers;

    //INCENTIVE
    //Demand based pricing: if demand exceeds supply, the transaction cost can be higher than 1 Ether and vice versa
    //done by comparing the total supply of energy units in the market to the total demand of customers
    
    //transaction cost of buying a unit of energy
    uint transactionCost = 1 ether;

    //private function to get total energy available in the market
    function getTotalEnergySupply() private view returns (uint) {
        uint totalEnergySupply = 0;
        for (uint i = 0; i < sellers.length; i++) {
            totalEnergySupply += uint(prosumers[sellers[i]].energyStatus);
        }
        return totalEnergySupply;
    }

    //private function to get total demand from the buyers array
    function getTotalEnergyDemand() private view returns (uint) {
        uint totalEnergyDemand = 0;
        for (uint i = 0; i < buyers.length; i++) {
            totalEnergyDemand += uint(abs(prosumers[buyers[i]].energyStatus));
        }
        return totalEnergyDemand;
    }

    //private function to get variable transaction cost
    function getVariableTransactionCost() private returns (uint) {
        uint totalSupply = getTotalEnergySupply();
        uint totalDemand = getTotalEnergyDemand();
        uint freeEnergy = totalSupply - totalDemand;
        if (freeEnergy == 0) {
            return transactionCost;
        }
        
        else if (freeEnergy < 0) {
            transactionCost = 1.25 ether;
            return transactionCost;
        } 

        else if (freeEnergy > 0) {
            transactionCost = 0.75 ether;
            return transactionCost;
        }
        else {
            return transactionCost;
        }
        
    }

    //public function for trading 
    function trade() public {
        
        for (uint i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            int energyToBuy = prosumers[buyer].energyStatus;
            for (uint j = 0; j < sellers.length; j++) {
                address seller = sellers[j];
                int energyToSell = prosumers[seller].energyStatus;
                if (energyToBuy < 0 && energyToSell > 0) {
                    uint energyToTrade = uint(min(abs(energyToBuy), abs(energyToSell)));
                    uint price = energyToTrade * getVariableTransactionCost();
                    prosumers[buyer].balance -= price;
                    prosumers[seller].balance += price;
                    prosumers[buyer].energyStatus += int(energyToTrade);
                    prosumers[seller].energyStatus -= int(energyToTrade);
                    energyToBuy += int(energyToTrade);
                    energyToSell -= int(energyToTrade);
                    if (energyToSell == 0) {
                        delete sellers[j];
                    } else {
                        prosumers[seller].energyStatus = energyToSell;
                    }
                }
            }
            if (energyToBuy != 0) {
                prosumers[buyer].energyStatus = energyToBuy;
            } else {
                delete P2P.buyers[i];
            }
        }
    }

}

contract Main is P2P {
    

    //modifier to check if prosumer is registered
    modifier checkIfRegistered() {
        require(prosumers[msg.sender].id != address(0), "Request Error: Prosumer is not registered. Kindly register before sending any requests.");
        _;
    }
    
    //modifier to check if a new prosumer is already registered
    modifier checkAlreadyRegistered() {
        require(prosumers[msg.sender].id == address(0), "Registration Error: Prosumer is already registered.");
        _;
    }
    
    //modifier to check if a buyer has enough Ethers
    modifier hasSufficientEthers(int energy) {
        require(prosumers[msg.sender].balance >= uint(P2P.abs(energy)), "You have an insufficient Ether balance to process this request");
        _;
    }

    //public function to register prosumer
    function registerProsumer() public override checkAlreadyRegistered {
        P2P.registerProsumer();
    }  
    
    //public function to deposit Ethers
    function depositEthers() public payable checkIfRegistered {
        require(msg.value > 0, "You need to enter a value greater than 0 to deposit some Ethers");
        prosumers[msg.sender].balance += msg.value;
    }

    //public function to make a buying or selling request
    function makeEnergyRequest(int energy) public checkIfRegistered hasSufficientEthers(energy) {
        if (energy > 0) {
            P2P.sellers.push(msg.sender);
        } else {
            P2P.buyers.push(msg.sender);
        }
        prosumers[msg.sender].energyStatus = energy;
    }

    //public function to check current energy status of prosumer
    function checkEnergyStatus() public view checkIfRegistered returns (int) {
        return prosumers[msg.sender].energyStatus;
    }

    //public function to check current Ether balance of prosumer
    function checkBalance() public view checkIfRegistered returns (uint) {
        return prosumers[msg.sender].balance;
    }

    //public function to withdraw Ethers
    function withdrawEthers() public payable checkIfRegistered {
        require(prosumers[msg.sender].energyStatus >= 0, "You're at an energy deficit (your status is below 0). Cannot withdraw ethers");
        uint balance = prosumers[msg.sender].balance;
        require(balance > 0, "You have insufficient ethers to complete this request");
        require(msg.value <= balance , "Withdrawal amount exceeds available balance");
        prosumers[msg.sender].balance = 0;
        payable(msg.sender).transfer(balance);
    }
    
    //private function to get list of buyers
    function getBuyers() private view returns (address[] memory) {
        return (P2P.buyers);
    }

    //private function to get list of sellers
    function getSellers() private view returns (address[] memory) {
        return (P2P.sellers);
    }

    //public function to get a user's account details
    function getProsumerDetails() private view returns (address, int, uint) {
        Prosumer storage prosumer = prosumers[msg.sender];
        return (msg.sender, prosumer.energyStatus, prosumer.balance);
    } 
    
}