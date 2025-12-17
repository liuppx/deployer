// scripts/extract-abi.js
const fs = require("fs");
const path = require("path");

// 合约名称
const contractName = "Erc20Token";

// 读取编译后的合约JSON文件
const contractJsonPath = path.join(
  __dirname,
  "..",
  "artifacts",
  "contracts",
  `${contractName}.sol`,
  `${contractName}.json`
);

const contractJson = require(contractJsonPath);

// 提取ABI
const abi = contractJson.abi;

// 将ABI保存到单独的文件
fs.writeFileSync(
  path.join(__dirname, "../artifacts", `${contractName}-abi.json`),
  JSON.stringify(abi, null, 2)
);

console.log(`ABI for ${contractName} has been saved to ${contractName}-abi.json`);
