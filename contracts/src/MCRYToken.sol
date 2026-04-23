// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MCRYToken {
    string public constant name = "Delivera Token";
    string public constant symbol = "MON";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply, address treasury) {
        require(treasury != address(0), "Treasury zero");
        totalSupply = initialSupply;
        balanceOf[treasury] = initialSupply;
        emit Transfer(address(0), treasury, initialSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "Allowance low");
        unchecked {
            allowance[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "To zero");
        uint256 senderBalance = balanceOf[from];
        require(senderBalance >= amount, "Balance low");
        unchecked {
            balanceOf[from] = senderBalance - amount;
        }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
