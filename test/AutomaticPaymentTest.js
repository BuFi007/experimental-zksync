const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("AutomaticPayments with MetaTransactions", function () {
  let automaticPayments;
  let trustedForwarder;
  let mockToken;
  let owner;
  let payer;
  let payee;
  let other;

  // Helper function to create and sign a meta-transaction
  async function createSignedRequest(from, to, data) {
    const nonce = await trustedForwarder.getNonce(from.address);
    const gas = 500000; // Example gas limit

    const request = {
      from: from.address,
      to: to,
      value: 0,
      gas: gas,
      nonce: nonce,
      data: data,
    };

    // Create the EIP-712 signature
    const domain = {
      name: "TrustedForwarder",
      version: "1",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: trustedForwarder.target,
    };

    const types = {
      ForwardRequest: [
        { name: "from", type: "address" },
        { name: "to", type: "address" },
        { name: "value", type: "uint256" },
        { name: "gas", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "data", type: "bytes" },
      ],
    };

    const signature = await from.signTypedData(domain, types, request);
    return { request, signature };
  }

  beforeEach(async function () {
    [owner, payer, payee, other] = await ethers.getSigners();

    // Deploy TrustedForwarder
    const TrustedForwarder = await ethers.getContractFactory(
      "TrustedForwarder"
    );
    trustedForwarder = await TrustedForwarder.deploy();

    // Deploy MockERC20
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockToken = await MockERC20.deploy("MockToken", "MTK");
    await mockToken.mint(payer.address, ethers.parseEther("1000"));

    // Deploy AutomaticPayments
    const AutomaticPayments = await ethers.getContractFactory(
      "AutomaticPayments"
    );
    automaticPayments = await AutomaticPayments.deploy(trustedForwarder.target);

    // Approve tokens
    await mockToken
      .connect(payer)
      .approve(automaticPayments.target, ethers.parseEther("1000"));
  });

  describe("Meta-transaction Authorization", function () {
    it("should authorize payment through meta-transaction", async function () {
      const amount = ethers.parseEther("100");
      const frequency = 86400; // 1 day
      const validUntil = (await time.latest()) + 2592000; // 30 days from now

      const authorizeData = automaticPayments.interface.encodeFunctionData(
        "authorizePayment",
        [payee.address, amount, frequency, validUntil, mockToken.target]
      );

      const { request, signature } = await createSignedRequest(
        payer,
        automaticPayments.target,
        authorizeData
      );

      await expect(trustedForwarder.execute(request, signature))
        .to.emit(automaticPayments, "PaymentAuthorized")
        .withArgs(
          payer.address,
          payee.address,
          amount,
          frequency,
          validUntil,
          mockToken.target
        );

      const payment = await automaticPayments.getPaymentInfo(
        payer.address,
        payee.address
      );
      expect(payment.isActive).to.be.true;
      expect(payment.amount).to.equal(amount);
    });

    it("should execute payment through meta-transaction", async function () {
      // First authorize a payment
      const amount = ethers.parseEther("100");
      const frequency = 86400;
      const validUntil = (await time.latest()) + 2592000;

      await automaticPayments
        .connect(payer)
        .authorizePayment(
          payee.address,
          amount,
          frequency,
          validUntil,
          mockToken.target
        );

      // Execute payment through meta-transaction
      const executeData = automaticPayments.interface.encodeFunctionData(
        "executePayment",
        [payer.address, payee.address]
      );

      const { request, signature } = await createSignedRequest(
        other, // Anyone can execute the payment
        automaticPayments.target,
        executeData
      );

      const initialPayeeBalance = await mockToken.balanceOf(payee.address);

      await expect(trustedForwarder.execute(request, signature)).to.emit(
        automaticPayments,
        "PaymentExecuted"
      );

      const finalPayeeBalance = await mockToken.balanceOf(payee.address);
      expect(finalPayeeBalance - initialPayeeBalance).to.equal(amount);
    });

    it("should cancel payment through meta-transaction", async function () {
      // First authorize a payment
      const amount = ethers.parseEther("100");
      const frequency = 86400;
      const validUntil = (await time.latest()) + 2592000;

      await automaticPayments
        .connect(payer)
        .authorizePayment(
          payee.address,
          amount,
          frequency,
          validUntil,
          mockToken.target
        );

      // Cancel payment through meta-transaction
      const cancelData = automaticPayments.interface.encodeFunctionData(
        "cancelPayment",
        [payee.address]
      );

      const { request, signature } = await createSignedRequest(
        payer,
        automaticPayments.target,
        cancelData
      );

      await expect(trustedForwarder.execute(request, signature))
        .to.emit(automaticPayments, "PaymentCancelled")
        .withArgs(payer.address, payee.address);

      const payment = await automaticPayments.getPaymentInfo(
        payer.address,
        payee.address
      );
      expect(payment.isActive).to.be.false;
    });
  });
});
