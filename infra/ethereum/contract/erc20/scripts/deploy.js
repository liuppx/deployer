// scripts/deploy.js
const hre = require("hardhat");
const fs = require('fs');
const path = require('path');

async function main() {
    console.log("🏓 Deploying Erc20 Token to Devnet...");

    try {
        // 获取部署账户
        const [deployer] = await hre.ethers.getSigners();
        console.log("-------------start------");
        console.log("Deploying contracts with account:", deployer.address);

        // 检查账户余额
        const balance = await hre.ethers.provider.getBalance(deployer.address);
        console.log("Account balance:", hre.ethers.formatEther(balance), "ETH");

        // 检查余额是否足够
        const minBalance = hre.ethers.parseEther("0.01"); // 至少需要 0.01 ETH
        if (balance < minBalance) {
            throw new Error(`Insufficient balance. Need at least 0.01 ETH, but got ${hre.ethers.formatEther(balance)} ETH`);
        }

        // 部署合约参数
        const decimals = 6
        const initialSupply = hre.ethers.parseUnits("1000000", decimals); // 1,000,000 tokens
        console.log("Initial supply:", hre.ethers.formatUnits(initialSupply, decimals), "tokens");

        // 获取合约工厂
        console.log("Getting contract factory...");
        const Erc20Token = await hre.ethers.getContractFactory("Erc20Token");

        // 获取当前网络的 gas 价格
        const feeData = await hre.ethers.provider.getFeeData();
        console.log("Current gas price:", hre.ethers.formatUnits(feeData.gasPrice || 0, "gwei"), "Gwei");

        // 部署选项
        const deployOptions = {
            gasLimit: 2000000, // 手动设置 gas limit，避免 estimateGas 错误
        };

        // 如果网络支持 EIP-1559，使用 maxFeePerGas 和 maxPriorityFeePerGas
        if (feeData.maxFeePerGas && feeData.maxPriorityFeePerGas) {
            deployOptions.maxFeePerGas = feeData.maxFeePerGas;
            deployOptions.maxPriorityFeePerGas = feeData.maxPriorityFeePerGas;
            console.log("Using EIP-1559 gas pricing");
        } else if (feeData.gasPrice) {
            deployOptions.gasPrice = feeData.gasPrice;
            console.log("Using legacy gas pricing");
        }

        console.log("Deploying Erc20Token with options:", deployOptions);

        // 部署合约
        const erc20Token = await Erc20Token.deploy(initialSupply, deployOptions);

        console.log("Waiting for deployment transaction...");
        
        // 等待部署交易被挖掘
        const deploymentTx = erc20Token.deploymentTransaction();
        if (deploymentTx) {
            console.log("Deployment transaction hash:", deploymentTx.hash);
            await deploymentTx.wait(1); // 等待 1 个确认
        }

        // 获取合约地址
        const contractAddress = await erc20Token.getAddress();
        console.log("✅ Erc20Token deployed to:", contractAddress);

        // 等待几个区块确认
        console.log("Waiting for additional confirmations...");
        if (deploymentTx) {
            await deploymentTx.wait(3); // 等待 3 个确认
        }

        // 验证部署
        console.log("\n📋 Verifying Contract Deployment:");
        
        try {
            const name = await erc20Token.name();
            const symbol = await erc20Token.symbol();
            const decimals = await erc20Token.decimals();
            const totalSupply = await erc20Token.totalSupply();
            const owner = await erc20Token.owner();
            const ownerBalance = await erc20Token.balanceOf(deployer.address);

            console.log("Name:", name);
            console.log("Symbol:", symbol);
            console.log("Decimals:", decimals);
            console.log("Total Supply:", hre.ethers.formatUnits(totalSupply, decimals));
            console.log("Owner:", owner);
            console.log("Owner Balance:", hre.ethers.formatUnits(ownerBalance, decimals));

            // 验证数据一致性
            if (totalSupply.toString() !== initialSupply.toString()) {
                console.warn("⚠️  Warning: Total supply doesn't match initial supply");
            }
            if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
                console.warn("⚠️  Warning: Owner doesn't match deployer");
            }

        } catch (verificationError) {
            console.error("❌ Contract verification failed:", verificationError.message);
            throw verificationError;
        }

        // 获取部署交易详情
        let transactionHash = "";
        let gasUsed = 0;
        let effectiveGasPrice = 0;

        if (deploymentTx) {
            transactionHash = deploymentTx.hash;
            try {
                const receipt = await hre.ethers.provider.getTransactionReceipt(transactionHash);
                if (receipt) {
                    gasUsed = receipt.gasUsed;
                    effectiveGasPrice = receipt.effectiveGasPrice || receipt.gasPrice || 0;
                    console.log("Gas used:", gasUsed.toString());
                    console.log("Effective gas price:", hre.ethers.formatUnits(effectiveGasPrice, "gwei"), "Gwei");
                    console.log("Total cost:", hre.ethers.formatEther(gasUsed * effectiveGasPrice), "ETH");
                }
            } catch (receiptError) {
                console.warn("Could not get transaction receipt:", receiptError.message);
            }
        }

        // 保存部署信息
        const deploymentInfo = {
            network: hre.network.name,
            networkId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
            contractName: "Erc20Token",
            contractAddress: contractAddress,
            deployer: deployer.address,
            deploymentTime: new Date().toISOString(),
            initialSupply: hre.ethers.formatUnits(initialSupply, decimals),
            transactionHash: transactionHash,
            gasUsed: gasUsed.toString(),
            effectiveGasPrice: effectiveGasPrice.toString(),
            deploymentCost: gasUsed > 0 ? hre.ethers.formatEther(BigInt(gasUsed) * BigInt(effectiveGasPrice)) : "0",
            blockNumber: deploymentTx ? (await deploymentTx.wait()).blockNumber : 0
        };

        // 确保 deployments 目录存在
        const deploymentsDir = path.join(__dirname, '..', 'deployments');
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }

        // 保存到网络特定的文件
        const deploymentFile = path.join(deploymentsDir, `${hre.network.name}-deployment.json`);
        fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
        
        // 也保存一个通用的文件（向后兼容）
        const generalFile = path.join(__dirname, '..', 'deployment-info.json');
        fs.writeFileSync(generalFile, JSON.stringify(deploymentInfo, null, 2));

        console.log(`\n📄 Deployment info saved to:`);
        console.log(`   - ${deploymentFile}`);
        console.log(`   - ${generalFile}`);

        // 输出有用的信息
        console.log("\n🎉 Deployment Summary:");
        console.log("=".repeat(50));
        console.log(`Contract: Erc20Token`);
        console.log(`Address: ${contractAddress}`);
        console.log(`Network: ${hre.network.name}`);
        console.log(`Deployer: ${deployer.address}`);
        console.log(`Transaction: ${transactionHash}`);
        console.log("=".repeat(50));

        return {
            contract: erc20Token,
            address: contractAddress,
            deploymentInfo: deploymentInfo
        };

    } catch (error) {
        console.error("\n❌ Deployment Error Details:");
        console.error("Error message:", error.message);
        
        if (error.code) {
            console.error("Error code:", error.code);
        }
        
        if (error.reason) {
            console.error("Error reason:", error.reason);
        }

        if (error.transaction) {
            console.error("Failed transaction:", error.transaction);
        }

        // 提供一些常见错误的解决建议
        if (error.message.includes("insufficient funds")) {
            console.error("\n💡 Solution: Add more ETH to your account");
        } else if (error.message.includes("gas")) {
            console.error("\n💡 Solution: Try adjusting gas settings or check network congestion");
        } else if (error.message.includes("nonce")) {
            console.error("\n💡 Solution: Reset your wallet nonce or wait for pending transactions");
        }

        throw error;
    }
}

// 如果直接运行此脚本
if (require.main === module) {
    main()
        .then(() => {
            console.log("\n✅ Deployment completed successfully!");
            process.exit(0);
        })
        .catch((error) => {
            console.error("\n❌ Deployment failed!");
            process.exit(1);
        });
}

module.exports = main;

