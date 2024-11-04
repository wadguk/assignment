require("@nomicfoundation/hardhat-toolbox");
require('hardhat-ignore-warnings');
require("dotenv").config();


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.27",

  networks: {
    hardhat: {
      forking: {
        url: process.env.MAINNET_RPC_URL,
        blockNumber: 21106617
      }
    }
  }
};
