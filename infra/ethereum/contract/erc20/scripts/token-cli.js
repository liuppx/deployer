// scripts/token-cli.js
const { ethers } = require('ethers');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

// 加载 .env 文件
require('dotenv').config();

// 创建命令行交互界面
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// 网络配置
const NETWORKS = {
  LOCALHOST: {
    name: 'Localhost',
    rpcUrlKey: 'LOCALHOST_RPC_URL',
    chainIdKey: 'LOCALHOST_CHAIN_ID',
    browserUrlKey: 'LOCALHOST_BROWSER_URL',
    defaultRpcUrl: 'http://127.0.0.1:8545',
    defaultChainId: '31337',
    defaultBrowserUrl: 'http://localhost:8545'
  },
  SEPOLIA: {
    name: 'Sepolia Testnet',
    rpcUrlKey: 'SEPOLIA_RPC_URL',
    chainIdKey: 'SEPOLIA_CHAIN_ID',
    browserUrlKey: 'SEPOLIA_BROWSER_URL',
    defaultRpcUrl: '',
    defaultChainId: '11155111',
    defaultBrowserUrl: 'https://sepolia.etherscan.io'
  },
  YEYING: {
    name: 'Yeying Network',
    rpcUrlKey: 'YEYING_RPC_URL',
    chainIdKey: 'YEYING_CHAIN_ID',
    browserUrlKey: 'YEYING_BROWSER_URL',
    defaultRpcUrl: '',
    defaultChainId: '5432',
    defaultBrowserUrl: ''
  },
  MAINNET: {
    name: 'Ethereum Mainnet',
    rpcUrlKey: 'MAINNET_RPC_URL',
    chainIdKey: 'MAINNET_CHAIN_ID',
    browserUrlKey: 'MAINNET_BROWSER_URL',
    defaultRpcUrl: '',
    defaultChainId: '1',
    defaultBrowserUrl: 'https://etherscan.io'
  },
  BSC: {
    name: 'BSC Mainnet',
    rpcUrlKey: 'BSC_RPC_URL',
    chainIdKey: 'BSC_CHAIN_ID',
    browserUrlKey: 'BSC_BROWSER_URL',
    defaultRpcUrl: 'https://bsc-dataseed.binance.org',
    defaultChainId: '56',
    defaultBrowserUrl: 'https://bscscan.com'
  },
  POLYGON: {
    name: 'Polygon Mainnet',
    rpcUrlKey: 'POLYGON_RPC_URL',
    chainIdKey: 'POLYGON_CHAIN_ID',
    browserUrlKey: 'POLYGON_BROWSER_URL',
    defaultRpcUrl: 'https://polygon-rpc.com',
    defaultChainId: '137',
    defaultBrowserUrl: 'https://polygonscan.com'
  }
};

// ERC20 Token ABI
const tokenABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function owner() view returns (address)",
  "function mint(address to, uint256 amount)",
  "function burn(uint256 amount)",
  "event Transfer(address indexed from, address indexed to, uint256 value)"
];

// 全局变量
let provider;
let signer;
let tokenContract;
let userAddress;
let isOwner = false;
let tokenDecimals = 18;
let currentNetwork = null;
let contractAddress = null;

// 工具函数：提示输入（支持默认值）
function question(prompt, defaultValue = null) {
  return new Promise((resolve) => {
    const displayPrompt = defaultValue
      ? `${prompt} [${defaultValue}]: `
      : `${prompt}: `;

    rl.question(displayPrompt, (answer) => {
      resolve(answer.trim() || defaultValue);
    });
  });
}

// 工具函数：暂停
function pause(message = '\nPress Enter to continue...') {
  return new Promise((resolve) => {
    rl.question(message, () => resolve());
  });
}

// 工具函数：清屏
function clearScreen() {
  console.clear();
}

// 工具函数：显示交易链接
function showTransactionLink(txHash) {
  if (currentNetwork && currentNetwork.browserUrl) {
    console.log(`View on Explorer: ${currentNetwork.browserUrl}/tx/${txHash}`);
  }
}

// 工具函数：显示地址链接
function showAddressLink(address) {
  if (currentNetwork && currentNetwork.browserUrl) {
    console.log(`View on Explorer: ${currentNetwork.browserUrl}/address/${address}`);
  }
}

// 主菜单
async function showMainMenu() {
  clearScreen();
  console.log('╔════════════════════════════════════════╗');
  console.log('║     ERC20 Token CLI Tool v2.0          ║');
  console.log('╚════════════════════════════════════════╝');
  console.log('');
  console.log('1. Connect to Wallet');
  console.log('2. Show Token Information');
  console.log('3. Check Balance');
  console.log('4. Transfer Tokens');
  console.log('5. Mint Tokens (Owner Only)');
  console.log('6. Burn Tokens');
  console.log('7. Switch Network');
  console.log('8. Switch Contract');
  console.log('9. Exit');
  console.log('');
  console.log('─────────────────────────────────────────');

  if (signer) {
    console.log(`✓ Connected: ${userAddress.substring(0, 6)}...${userAddress.substring(38)}`);
    if (currentNetwork) {
      console.log(`✓ Network: ${currentNetwork.name} (Chain ID: ${currentNetwork.chainId})`);
    }
    if (contractAddress) {
      console.log(`✓ Contract: ${contractAddress.substring(0, 6)}...${contractAddress.substring(38)}`);
    }
    if (isOwner) {
      console.log('✓ Role: Contract Owner');
    }
  } else {
    console.log('✗ Not connected to wallet');
  }
  console.log('─────────────────────────────────────────');

  const answer = await question('\nSelect an option (1-9)');

  switch (answer) {
    case '1':
      await connectWallet();
      break;
    case '2':
      await showTokenInfo();
      break;
    case '3':
      await checkBalance();
      break;
    case '4':
      await transferTokens();
      break;
    case '5':
      await mintTokens();
      break;
    case '6':
      await burnTokens();
      break;
    case '7':
      await switchNetwork();
      break;
    case '8':
      await switchContract();
      break;
    case '9':
      console.log('\nGoodbye! 👋');
      rl.close();
      process.exit(0);
      break;
    default:
      console.log('\n❌ Invalid option. Please try again.');
      await pause();
      await showMainMenu();
  }
}

// 选择网络
async function selectNetwork() {
  clearScreen();
  console.log('=== Select Network ===\n');

  const networkKeys = Object.keys(NETWORKS);
  networkKeys.forEach((key, index) => {
    console.log(`${index + 1}. ${NETWORKS[key].name}`);
  });

  const answer = await question('\nSelect network (1-' + networkKeys.length + ')');
  const selectedIndex = parseInt(answer) - 1;

  if (selectedIndex < 0 || selectedIndex >= networkKeys.length) {
    console.log('\n❌ Invalid selection.');
    await pause();
    return null;
  }

  const networkKey = networkKeys[selectedIndex];
  const networkConfig = NETWORKS[networkKey];

  // 获取 RPC URL
  const envRpcUrl = process.env[networkConfig.rpcUrlKey];
  const rpcUrl = await question(
    `Enter RPC URL`,
    envRpcUrl || networkConfig.defaultRpcUrl
  );

  if (!rpcUrl) {
    console.log('\n❌ RPC URL is required.');
    await pause();
    return null;
  }

  // 获取 Chain ID
  const envChainId = process.env[networkConfig.chainIdKey];
  const chainId = await question(
    `Enter Chain ID`,
    envChainId || networkConfig.defaultChainId
  );

  // 获取 Browser URL
  const envBrowserUrl = process.env[networkConfig.browserUrlKey];
  const browserUrl = await question(
    `Enter Block Explorer URL (optional)`,
    envBrowserUrl || networkConfig.defaultBrowserUrl
  );

  return {
    name: networkConfig.name,
    rpcUrl,
    chainId,
    browserUrl: browserUrl || null
  };
}

// 连接钱包
async function connectWallet() {
  clearScreen();
  console.log('=== Connect to Wallet ===\n');

  try {
    // 选择网络
    const network = await selectNetwork();
    if (!network) {
      await showMainMenu();
      return;
    }

    console.log(`\n📡 Connecting to ${network.name}...`);

    // 创建 provider
    provider = new ethers.JsonRpcProvider(network.rpcUrl);

    // 验证连接
    try {
      const blockNumber = await provider.getBlockNumber();
      console.log(`✓ Connected to network (Block: ${blockNumber})`);
    } catch (error) {
      console.log(`\n❌ Failed to connect to RPC: ${error.message}`);
      await pause();
      await showMainMenu();
      return;
    }

    // 获取私钥
    const envPrivateKey = process.env.PRIVATE_KEY;
    let privateKey;

    if (envPrivateKey) {
      const useDefault = await question(
        `Use private key from .env? (y/n)`,
        'y'
      );

      if (useDefault.toLowerCase() === 'y') {
        privateKey = envPrivateKey;
      } else {
        privateKey = await question('Enter your private key');
      }
    } else {
      privateKey = await question('Enter your private key');
    }

    if (!privateKey) {
      console.log('\n❌ Private key is required.');
      await pause();
      await showMainMenu();
      return;
    }

    // 确保私钥格式正确
    if (!privateKey.startsWith('0x')) {
      privateKey = '0x' + privateKey;
    }

    // 创建 signer
    signer = new ethers.Wallet(privateKey, provider);
    userAddress = await signer.getAddress();
    currentNetwork = network;

    console.log(`\n✓ Wallet connected: ${userAddress}`);
    showAddressLink(userAddress);

    // 获取余额
    const balance = await provider.getBalance(userAddress);
    console.log(`✓ Balance: ${ethers.formatEther(balance)} ETH`);

    // 获取合约地址
    const envContractAddress = process.env.TOKEN_CONTRACT_ADDRESS;
    contractAddress = await question(
      'Enter token contract address',
      envContractAddress
    );

    if (!contractAddress) {
      console.log('\n⚠️  No contract address provided. You can set it later.');
      await pause();
      await showMainMenu();
      return;
    }

    if (!ethers.isAddress(contractAddress)) {
      console.log('\n❌ Invalid contract address format.');
      await pause();
      await showMainMenu();
      return;
    }

    // 创建合约实例
    tokenContract = new ethers.Contract(contractAddress, tokenABI, signer);

    // 获取代币信息
    try {
      const name = await tokenContract.name();
      const symbol = await tokenContract.symbol();
      tokenDecimals = await tokenContract.decimals();

      console.log(`\n✓ Connected to token: ${name} (${symbol})`);
      showAddressLink(contractAddress);

      // 检查是否是合约所有者
      try {
        const ownerAddress = await tokenContract.owner();
        isOwner = (ownerAddress.toLowerCase() === userAddress.toLowerCase());

        if (isOwner) {
          console.log('✓ You are the contract owner');
        }
      } catch (error) {
        // 合约可能没有 owner 函数
        console.log('ℹ️  Contract does not have an owner function');
      }

    } catch (error) {
      console.log(`\n❌ Failed to connect to contract: ${error.message}`);
      tokenContract = null;
      contractAddress = null;
    }

  } catch (error) {
    console.error(`\n❌ Error: ${error.message}`);
  }

  await pause();
  await showMainMenu();
}

// 切换网络
async function switchNetwork() {
  if (!signer) {
    console.log('\n❌ Please connect wallet first.');
    await pause();
    await showMainMenu();
    return;
  }

  await connectWallet();
}

// 切换合约
async function switchContract() {
  clearScreen();
  console.log('=== Switch Contract ===\n');

  if (!signer) {
    console.log('❌ Please connect wallet first.');
    await pause();
    await showMainMenu();
    return;
  }

  const newContractAddress = await question(
    'Enter new token contract address',
    contractAddress
  );

  if (!newContractAddress || !ethers.isAddress(newContractAddress)) {
    console.log('\n❌ Invalid contract address.');
    await pause();
    await showMainMenu();
    return;
  }

  try {
    tokenContract = new ethers.Contract(newContractAddress, tokenABI, signer);

    const name = await tokenContract.name();
    const symbol = await tokenContract.symbol();
    tokenDecimals = await tokenContract.decimals();
    contractAddress = newContractAddress;

    console.log(`\n✓ Switched to: ${name} (${symbol})`);
    showAddressLink(contractAddress);

    // 检查所有者
    try {
      const ownerAddress = await tokenContract.owner();
      isOwner = (ownerAddress.toLowerCase() === userAddress.toLowerCase());

      if (isOwner) {
        console.log('✓ You are the contract owner');
      }
    } catch (error) {
      isOwner = false;
    }

  } catch (error) {
    console.log(`\n❌ Failed to connect to contract: ${error.message}`);
  }

  await pause();
  await showMainMenu();
}

// 显示代币信息
async function showTokenInfo() {
  clearScreen();
  console.log('=== Token Information ===\n');

  if (!tokenContract) {
    console.log('❌ Not connected to a token contract. Please connect first.');
    await pause();
    await showMainMenu();
    return;
  }

  try {
    console.log('📊 Fetching token information...\n');

    // 获取代币信息
    const [name, symbol, decimals, totalSupply, userBalance, ownerAddress] = await Promise.all([
      tokenContract.name(),
      tokenContract.symbol(),
      tokenContract.decimals(),
      tokenContract.totalSupply(),
      tokenContract.balanceOf(userAddress),
      tokenContract.owner().catch(() => 'N/A')
    ]);

    // 格式化数值
    const formattedTotalSupply = ethers.formatUnits(totalSupply, decimals);
    const formattedUserBalance = ethers.formatUnits(userBalance, decimals);

    console.log('╔════════════════════════════════════════════════════╗');
    console.log(`  Token Name:       ${name}`);
    console.log(`  Token Symbol:     ${symbol}`);
    console.log(`  Decimals:         ${decimals}`);
    console.log(`  Total Supply:     ${formattedTotalSupply} ${symbol}`);
    console.log('╠════════════════════════════════════════════════════╣');
    console.log(`  Contract Address: ${contractAddress}`);
    console.log(`  Owner Address:    ${ownerAddress}`);
    console.log('╠════════════════════════════════════════════════════╣');
    console.log(`  Your Address:     ${userAddress}`);
    console.log(`  Your Balance:     ${formattedUserBalance} ${symbol}`);
    console.log(`  Is Owner:         ${isOwner ? 'Yes ✓' : 'No'}`);
    console.log('╚════════════════════════════════════════════════════╝');

    showAddressLink(contractAddress);

  } catch (error) {
    console.error(`\n❌ Error fetching token information: ${error.message}`);
  }

  await pause();
  await showMainMenu();
}

// 检查余额
async function checkBalance() {
  clearScreen();
  console.log('=== Check Balance ===\n');

  if (!tokenContract) {
    console.log('❌ Not connected to a token contract. Please connect first.');
    await pause();
    await showMainMenu();
    return;
  }

  const address = await question('Enter address to check (leave empty for your address)', userAddress);

  if (!ethers.isAddress(address)) {
    console.log('\n❌ Invalid address format.');
    await pause();
    await showMainMenu();
    return;
  }

  try {
    const balance = await tokenContract.balanceOf(address);
    const symbol = await tokenContract.symbol();
    const formattedBalance = ethers.formatUnits(balance, tokenDecimals);

    console.log(`\n📊 Balance Information:`);
    console.log(`   Address: ${address}`);
    console.log(`   Balance: ${formattedBalance} ${symbol}`);

    showAddressLink(address);

  } catch (error) {
    console.error(`\n❌ Error checking balance: ${error.message}`);
  }

  await pause();
  await showMainMenu();
}

// 转账代币
async function transferTokens() {
  clearScreen();
  console.log('=== Transfer Tokens ===\n');

  if (!tokenContract) {
    console.log('❌ Not connected to a token contract. Please connect first.');
    await pause();
    await showMainMenu();
    return;
  }

  try {
    // 显示当前余额
    const balance = await tokenContract.balanceOf(userAddress);
    const symbol = await tokenContract.symbol();
    const formattedBalance = ethers.formatUnits(balance, tokenDecimals);

    console.log(`Your current balance: ${formattedBalance} ${symbol}\n`);

    // 获取接收地址
    const toAddress = await question('Enter recipient address');

    if (!ethers.isAddress(toAddress)) {
      console.log('\n❌ Invalid address format.');
      await pause();
      await showMainMenu();
      return;
    }

    // 获取转账金额
    const amount = await question(`Enter amount to transfer`);

    const amountFloat = parseFloat(amount);
    if (isNaN(amountFloat) || amountFloat <= 0) {
      console.log('\n❌ Invalid amount. Please enter a positive number.');
      await pause();
      await showMainMenu();
      return;
    }

    // 转换为 wei
    const amountWei = ethers.parseUnits(amount, tokenDecimals);

    // 检查余额
    if (balance < amountWei) {
      console.log('\n❌ Insufficient balance for this transfer.');
      console.log(`   Required: ${amount} ${symbol}`);
      console.log(`   Available: ${formattedBalance} ${symbol}`);
      await pause();
      await showMainMenu();
      return;
    }

    // 确认转账
    console.log(`\n📋 Transfer Summary:`);
    console.log(`   From:     ${userAddress}`);
    console.log(`   To:       ${toAddress}`);
    console.log(`   Amount:   ${amount} ${symbol}`);
    console.log(`   Network:  ${currentNetwork?.name || 'Unknown'}`);

    const confirm = await question('\nConfirm transfer? (y/n)', 'n');

    if (confirm.toLowerCase() !== 'y') {
      console.log('\n❌ Transfer cancelled.');
      await pause();
      await showMainMenu();
      return;
    }

    console.log(`\n🔄 Sending transaction...`);

    // 发送交易
    const tx = await tokenContract.transfer(toAddress, amountWei);
    console.log(`✓ Transaction submitted: ${tx.hash}`);
    showTransactionLink(tx.hash);

    console.log('⏳ Waiting for confirmation...');

    // 等待交易确认
    const receipt = await tx.wait();

    console.log(`\n✅ Transfer successful!`);
    console.log(`   Block Number: ${receipt.blockNumber}`);
    console.log(`   Gas Used:     ${receipt.gasUsed.toString()}`);
    console.log(`   Status:       ${receipt.status === 1 ? 'Success' : 'Failed'}`);

    showTransactionLink(tx.hash);

  } catch (error) {
    console.error(`\n❌ Error transferring tokens: ${error.message}`);

    if (error.code === 'INSUFFICIENT_FUNDS') {
      console.log('💡 Tip: Make sure you have enough ETH for gas fees.');
    }
  }

  await pause();
  await showMainMenu();
}

// 铸造代币
async function mintTokens() {
  clearScreen();
  console.log('=== Mint Tokens (Owner Only) ===\n');

  if (!tokenContract) {
    console.log('❌ Not connected to a token contract. Please connect first.');
    await pause();
    await showMainMenu();
    return;
  }

  if (!isOwner) {
    console.log('❌ Only the contract owner can mint tokens.');
    console.log(`   Contract Owner: ${await tokenContract.owner()}`);
    console.log(`   Your Address:   ${userAddress}`);
    await pause();
    await showMainMenu();
    return;
  }

  try {
    const symbol = await tokenContract.symbol();
    const totalSupply = await tokenContract.totalSupply();
    const formattedSupply = ethers.formatUnits(totalSupply, tokenDecimals);

    console.log(`Current total supply: ${formattedSupply} ${symbol}\n`);

    // 获取接收地址
    const toAddress = await question('Enter recipient address', userAddress);

    if (!ethers.isAddress(toAddress)) {
      console.log('\n❌ Invalid address format.');
      await pause();
      await showMainMenu();
      return;
    }

    // 获取铸造金额
    const amount = await question(`Enter amount to mint`);

    const amountFloat = parseFloat(amount);
    if (isNaN(amountFloat) || amountFloat <= 0) {
      console.log('\n❌ Invalid amount. Please enter a positive number.');
      await pause();
      await showMainMenu();
      return;
    }

    // 转换为 wei
    const amountWei = ethers.parseUnits(amount, tokenDecimals);

    // 确认铸造
    console.log(`\n📋 Mint Summary:`);
    console.log(`   Recipient:    ${toAddress}`);
    console.log(`   Amount:       ${amount} ${symbol}`);
    console.log(`   New Supply:   ${parseFloat(formattedSupply) + amountFloat} ${symbol}`);
    console.log(`   Network:      ${currentNetwork?.name || 'Unknown'}`);

    const confirm = await question('\nConfirm minting? (y/n)', 'n');

    if (confirm.toLowerCase() !== 'y') {
      console.log('\n❌ Minting cancelled.');
      await pause();
      await showMainMenu();
      return;
    }

    console.log(`\n🔄 Sending transaction...`);

    // 发送交易
    const tx = await tokenContract.mint(toAddress, amountWei);
    console.log(`✓ Transaction submitted: ${tx.hash}`);
    showTransactionLink(tx.hash);

    console.log('⏳ Waiting for confirmation...');

    // 等待交易确认
    const receipt = await tx.wait();

    console.log(`\n✅ Minting successful!`);
    console.log(`   Block Number: ${receipt.blockNumber}`);
    console.log(`   Gas Used:     ${receipt.gasUsed.toString()}`);
    console.log(`   Status:       ${receipt.status === 1 ? 'Success' : 'Failed'}`);

    showTransactionLink(tx.hash);

  } catch (error) {
    console.error(`\n❌ Error minting tokens: ${error.message}`);

    if (error.code === 'INSUFFICIENT_FUNDS') {
      console.log('💡 Tip: Make sure you have enough ETH for gas fees.');
    }
  }

  await pause();
  await showMainMenu();
}

// 销毁代币
async function burnTokens() {
  clearScreen();
  console.log('=== Burn Tokens ===\n');

  if (!tokenContract) {
    console.log('❌ Not connected to a token contract. Please connect first.');
    await pause();
    await showMainMenu();
    return;
  }

  try {
    // 显示当前余额
    const balance = await tokenContract.balanceOf(userAddress);
    const symbol = await tokenContract.symbol();
    const formattedBalance = ethers.formatUnits(balance, tokenDecimals);

    console.log(`Your current balance: ${formattedBalance} ${symbol}\n`);

    if (balance === 0n) {
      console.log('❌ You have no tokens to burn.');
      await pause();
      await showMainMenu();
      return;
    }

    // 获取销毁金额
    const amount = await question(`Enter amount to burn`);

    const amountFloat = parseFloat(amount);
    if (isNaN(amountFloat) || amountFloat <= 0) {
      console.log('\n❌ Invalid amount. Please enter a positive number.');
      await pause();
      await showMainMenu();
      return;
    }

    // 转换为 wei
    const amountWei = ethers.parseUnits(amount, tokenDecimals);

    // 检查余额
    if (balance < amountWei) {
      console.log('\n❌ Insufficient balance for this burn operation.');
      console.log(`   Required:  ${amount} ${symbol}`);
      console.log(`   Available: ${formattedBalance} ${symbol}`);
      await pause();
      await showMainMenu();
      return;
    }

    // 确认销毁
    console.log(`\n📋 Burn Summary:`);
    console.log(`   Amount:           ${amount} ${symbol}`);
    console.log(`   Remaining:        ${parseFloat(formattedBalance) - amountFloat} ${symbol}`);
    console.log(`   Network:          ${currentNetwork?.name || 'Unknown'}`);
    console.log(`\n⚠️  Warning: This action is irreversible!`);

    const confirm = await question('\nConfirm burning? (y/n)', 'n');

    if (confirm.toLowerCase() !== 'y') {
      console.log('\n❌ Burning cancelled.');
      await pause();
      await showMainMenu();
      return;
    }

    console.log(`\n🔄 Sending transaction...`);

    // 发送交易
    const tx = await tokenContract.burn(amountWei);
    console.log(`✓ Transaction submitted: ${tx.hash}`);
    showTransactionLink(tx.hash);

    console.log('⏳ Waiting for confirmation...');

    // 等待交易确认
    const receipt = await tx.wait();

    console.log(`\n✅ Burning successful!`);
    console.log(`   Block Number: ${receipt.blockNumber}`);
    console.log(`   Gas Used:     ${receipt.gasUsed.toString()}`);
    console.log(`   Status:       ${receipt.status === 1 ? 'Success' : 'Failed'}`);

    showTransactionLink(tx.hash);

  } catch (error) {
    console.error(`\n❌ Error burning tokens: ${error.message}`);

    if (error.code === 'INSUFFICIENT_FUNDS') {
      console.log('💡 Tip: Make sure you have enough ETH for gas fees.');
    }
  }

  await pause();
  await showMainMenu();
}

// 错误处理
process.on('unhandledRejection', (error) => {
  console.error('\n❌ Unhandled error:', error.message);
  process.exit(1);
});

process.on('SIGINT', () => {
  console.log('\n\nGoodbye! 👋');
  rl.close();
  process.exit(0);
});

// 启动程序
console.log('🚀 Starting ERC20 Token CLI Tool...\n');
setTimeout(() => {
  showMainMenu();
}, 500);

