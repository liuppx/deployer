// contract-event-listener.js
const { Web3 } = require('web3');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// 全局变量
let web3;
let contract;
let decimals;
let eventSubscription;
let reconnectAttempts = 0;
const MAX_RECONNECT_ATTEMPTS = parseInt(process.env.MAX_RETRIES || '3');
const RECONNECT_INTERVAL = parseInt(process.env.RECONNECT_INTERVAL || '5000');

/**
 * 初始化Web3连接
 */
function initWeb3() {
    try {
        const rpcUrl = process.env.LISTEN_RPC_URL || 'http://localhost:8545';
        console.log(`连接到RPC: ${rpcUrl}`);

        // 检查是否是WebSocket URL
        if (rpcUrl.startsWith('ws://') || rpcUrl.startsWith('wss://')) {
            web3 = new Web3(rpcUrl);
        } else {
            // 对于HTTP连接，我们需要使用轮询
            web3 = new Web3(rpcUrl);
            console.warn('警告: 使用HTTP连接，将使用轮询方式监听事件，这不是实时的');
        }

        // 初始化合约
        const contractAddress = process.env.LISTEN_CONTRACT_ADDRESS;
        const contractAbiPath = process.env.LISTEN_CONTRACT_ABI_PATH || './Erc20Token-abi.json';

        console.log(`监听合约: ${contractAddress}`);

        // 读取合约ABI
        const contractAbi = JSON.parse(fs.readFileSync(contractAbiPath, 'utf8'));

        // 创建合约实例
        contract = new web3.eth.Contract(contractAbi, contractAddress);

        // 重置重连计数
        reconnectAttempts = 0;

        return true;
    } catch (error) {
        console.error('初始化Web3失败:', error);
        return false;
    }
}

/**
 * 处理Web3连接断开
 */
async function handleDisconnect() {
    console.log('Web3连接已断开');

    if (eventSubscription) {
        try {
            await eventSubscription.unsubscribe();
            console.log('已取消事件订阅');
        } catch (error) {
            console.error('取消事件订阅失败:', error.message);
        }
        eventSubscription = null;
    }

    // 尝试重新连接
    reconnectAttempts++;
    if (reconnectAttempts <= MAX_RECONNECT_ATTEMPTS) {
        console.log(`尝试重新连接 (${reconnectAttempts})...`);
        setTimeout(() => {
            if (initWeb3()) {
                subscribeToEvents();
            }
        }, RECONNECT_INTERVAL);
    } else {
        console.error(`达到最大重连次数 (${MAX_RECONNECT_ATTEMPTS})，停止重连`);
    }
}

/**
 * 记录事件到日志文件
 * @param {Object} event - 事件对象
 */
function logEvent(event) {
    try {
        const logFilePath = process.env.LISTEN_LOG_FILE_PATH || './events.log';
        event = JSON.parse(JSON.stringify(event, (key, value) =>
            typeof value === 'bigint' ? value.toString() : value
        ));
        const logData = JSON.stringify({
            timestamp: new Date().toISOString(),
            event: event.event,
            blockNumber: event.blockNumber,
            transactionHash: event.transactionHash,
            returnValues: event.returnValues
        }, null, 2);

        fs.appendFileSync(logFilePath, logData + ',\n');
    } catch (error) {
        console.error('记录事件失败:', error);
    }
}

/**
 * 格式化代币金额 - 将最小单位的代币数量转换为可读的十进制格式
 * 例如：将 1500000 (USDC最小单位) 转换为 "1.5" (实际USDC数量)
 * 
 * @param {string|number|BigInt} value - 代币的最小单位数量（如 wei、satoshi 等）
 * @param {string|number} decimals - 代币的小数位数（如 ETH=18, USDC=6）
 * @returns {string} 格式化后的代币数量字符串
 * 
 * @example
 * formatTokenAmount('1000000', 6)     // 返回 "1" (1 USDC)
 * formatTokenAmount('1500000', 6)     // 返回 "1.5" (1.5 USDC)  
 * formatTokenAmount('1000000000000000000', 18) // 返回 "1" (1 ETH)
 */
function formatTokenAmount(value, decimals) {
    try {
        const valueStr = value.toString();
        const decimalPlaces = parseInt(decimals);

        // 使用 BigInt 进行计算（Web3 4.x 原生支持）
        const valueBigInt = BigInt(valueStr);
        const divisor = BigInt(10 ** decimalPlaces);

        const quotient = valueBigInt / divisor;
        const remainder = valueBigInt % divisor;

        if (remainder === 0n) {
            return quotient.toString();
        }

        const remainderStr = remainder.toString().padStart(decimalPlaces, '0');
        const trimmedRemainder = remainderStr.replace(/0+$/, '');

        return trimmedRemainder ? `${quotient.toString()}.${trimmedRemainder}` : quotient.toString();

    } catch (error) {
        console.error('格式化失败:', error);
        return value.toString();
    }
}

/**
 * 处理Transfer事件
 * @param {Object} values - 事件参数
 * @param {Object} event - 完整事件对象
 */
async function handleTransferEvent(values, event) {
    const { from, to, value } = values;

    console.log(`检测到Transfer事件: ${from} -> ${to}, 金额: ${formatTokenAmount(value, decimals)} TEST`);

    // 这里添加你的业务逻辑
    // 例如: 更新数据库、发送通知等

    // 记录事件到日志文件
    logEvent(event);
}

/**
 * 处理Approval事件
 * @param {Object} values - 事件参数
 * @param {Object} event - 完整事件对象
 */
async function handleApprovalEvent(values, event) {
    const { owner, spender, value } = values;

    console.log(`检测到Approval事件: ${owner} 授权 ${spender}, 金额: ${formatTokenAmount(value, decimals)} TEST`);

    // 这里添加你的业务逻辑
    // 例如: 更新数据库、发送通知等

    // 记录事件到日志文件
    logEvent(event);
}

/**
 * 处理事件
 * @param {Object} event - 事件对象
 */
async function handleEvent(event) {
    try {
        console.log(`\n接收到事件: ${event.event}`);
        console.log(`区块号: ${event.blockNumber}`);
        console.log(`交易哈希: ${event.transactionHash}`);

        const eventName = event.event;
        const eventValues = event.returnValues;

        // 根据事件类型调用不同的处理函数
        switch (eventName) {
            case 'Transfer':
                await handleTransferEvent(eventValues, event);
                break;
            case 'Approval':
                await handleApprovalEvent(eventValues, event);
                break;
            // 添加其他你关心的事件处理逻辑
            default:
                console.log(`未定义处理程序的事件: ${eventName}`);
                // 记录所有事件
                logEvent(event);
        }
    } catch (error) {
        console.error('处理事件失败:', error);
    }
}

/**
 * 订阅合约事件
 */
async function subscribeToEvents() {
    try {
        console.log('开始订阅合约事件...');

        // 确定起始区块
        const fromBlock = process.env.INCLUDE_HISTORICAL === 'true'
            ? (process.env.FROM_BLOCK || 0)
            : 'latest';

        console.log(`从区块 ${fromBlock} 开始监听事件`);

        // 使用Web3 v4.x的事件订阅方式
        if (web3.provider.constructor.name === 'WebsocketProvider') {
            // WebSocket连接 - 使用实时订阅
            eventSubscription = await contract.events.allEvents({
                fromBlock: fromBlock
            })
                .on('data', handleEvent)
                .on('error', error => {
                    console.error('事件订阅错误:', error);
                    handleDisconnect();
                });

            console.log('事件订阅已创建');
        } else {
            // HTTP连接 - 使用轮询
            console.log('使用HTTP连接，将通过轮询方式监听事件');

            // 初始区块号
            let lastCheckedBlock = fromBlock === 'latest'
                ? await web3.eth.getBlockNumber()
                : parseInt(fromBlock);

            // 设置轮询间隔
            setInterval(async () => {
                try {
                    const currentBlock = await web3.eth.getBlockNumber();

                    if (currentBlock > lastCheckedBlock) {
                        console.log(`检查新区块中的事件: ${lastCheckedBlock + 1n} 到 ${currentBlock}`);

                        // 获取指定区块范围内的事件
                        const events = await contract.getPastEvents('allEvents', {
                            fromBlock: lastCheckedBlock + 1n,
                            toBlock: currentBlock
                        });

                        // 处理找到的事件
                        for (const event of events) {
                            await handleEvent(event);
                        }

                        // 更新最后检查的区块
                        lastCheckedBlock = currentBlock;
                    }
                } catch (error) {
                    console.error('轮询事件失败:', error);
                }
            }, 10000); // 每10秒轮询一次
        }

        console.log('事件监听服务已启动并运行中...');
    } catch (error) {
        console.error('订阅事件失败:', error);
        handleDisconnect();
    }
}

/**
 * 主函数
 */
async function main() {
    console.log('启动合约事件监听服务...');

    // 初始化Web3
    if (initWeb3()) {
        decimals = await contract.methods.decimals().call();
        console.log('代币精度:', decimals);
        // 订阅事件
        await subscribeToEvents();
    } else {
        console.error('初始化失败，无法启动服务');
        process.exit(1);
    }
}

// 处理进程退出
process.on('SIGINT', async () => {
    console.log('接收到终止信号，正在关闭服务...');

    // 取消事件订阅
    if (eventSubscription) {
        try {
            await eventSubscription.unsubscribe();
            console.log('已取消事件订阅');
        } catch (error) {
            console.error('取消事件订阅失败:', error.message);
        }
    }

    console.log('服务已安全关闭');
    process.exit(0);
});

// 启动主函数
main().catch(error => {
    console.error('服务启动失败:', error);
    process.exit(1);
});

