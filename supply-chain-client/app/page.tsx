"use client";

import React, { useState, useEffect, useCallback } from "react";
import { ethers } from "ethers";
import {
  Truck,
  Package,
  CheckCircle,
  Clock,
  Wallet,
  Box,
  Factory,
  MapPin,
  Plus,
  Send,
  ShieldCheck,
  Database,
  Users,
  AlertCircle,
  Coins,
  DollarSign,
} from "lucide-react";

// --- CONTRACT CONFIGURATION ---
const CONTRACT_ADDRESS = "0xd0E052Ff24a7C55Dc825c5a07db9a05ED2807395"; // SupplyChainRWA
const PAYMENT_ESCROW_ADDRESS = "0xfd5B45aFEB521B488285Ff1c88a410D17571a78C"; // Escrow
const PRODUCT_NFT_ADDRESS = "0x6D0899d034C979d4dE160A984d25D6F0DcDE3f8E"; // ProductNFT
const USDC_ADDRESS = "0x40fD2Da7183F68305ff260677BD1d5c783F2bb97"; // MockUSDC

const SUPPLY_CHAIN_ABI = [
  // --- Standard Functions ---
  "function shipmentCounter() view returns (uint256)",
  "function shipments(uint256) view returns (int256 destLat, int256 destLong, uint256 radius, address manufacturer, uint256 rawMaterialId, uint256 amount, uint8 status, uint256 expectedArrivalTime, uint256 lastCheckTimestamp)",
  "function shipmentConsumed(uint256) view returns (bool)",
  "function hasRole(bytes32, address) view returns (bool)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)",
  "function SUPPLIER_ROLE() view returns (bytes32)",
  "function MANUFACTURER_ROLE() view returns (bytes32)",
  "function grantRole(bytes32 role, address account)",
  "function mint(address account, uint256 id, uint256 amount, bytes data)",
  // FIXED: Removed extra argument from createShipment
  "function createShipment(int256 destLat, int256 destLong, uint256 radius, address manufacturer, uint256 rawMaterialId, uint256 amount, uint256 expectedArrivalTime)",
  "function startDelivery(uint256 shipmentId)",
  "function assembleProduct(uint256 shipmentId, string[] metadataURIs)",
  "function balanceOf(address account, uint256 id) view returns (uint256)",
  // --- Demo / Hackathon Functions ---
  "function demoJoinAsSupplier()",
  "function demoJoinAsManufacturer()",
  // ADDED: Force Arrival for Manufacturer
  "function manufacturerForceArrival(uint256 shipmentId)",
];

const PAYMENT_ESCROW_ABI = [
  "function createEscrow(uint256 shipmentId, address supplier, uint256 amount)",
  "function releasePayment(uint256 shipmentId)",
  "function refundEscrow(uint256 shipmentId)",
  "function escrowDetails(uint256) view returns (address manufacturer, address supplier, uint256 amount, bool isFunded, bool isReleased, bool isRefunded)",
];

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
];

// --- COMPONENT: WIZARD OF OZ ONBOARDING MODAL ---
const JoinNetworkModal = ({
  roleType,
  onClose,
  onConfirm,
}: {
  roleType: string;
  onClose: () => void;
  onConfirm: () => Promise<void>;
}) => {
  const [step, setStep] = useState<"form" | "verifying" | "success">("form");
  const [formData, setFormData] = useState({ company: "", license: "" });
  const [error, setError] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setStep("verifying");
    try {
      await new Promise((resolve) => setTimeout(resolve, 2000)); // Fake Delay
      await onConfirm();
      setStep("success");
      setTimeout(() => {
        window.location.reload();
      }, 2000);
    } catch (e: any) {
      setStep("form");
      setError(e.message || "Transaction failed");
    }
  };

  return (
    <div className="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50 p-4">
      <div className="bg-slate-900 rounded-2xl max-w-md w-full p-6 shadow-2xl relative overflow-hidden border border-slate-700 animate-slide-up">
        {step === "form" && (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="text-center mb-6">
              <div
                className={`w-16 h-16 mx-auto rounded-full flex items-center justify-center mb-4 ${
                  roleType === "supplier"
                    ? "bg-blue-900/50 text-blue-400"
                    : "bg-green-900/50 text-green-400"
                }`}
              >
                {roleType === "supplier" ? (
                  <Database className="w-8 h-8" />
                ) : (
                  <Factory className="w-8 h-8" />
                )}
              </div>
              <h2 className="text-2xl font-bold text-white capitalize">
                Join as {roleType}
              </h2>
              <p className="text-gray-400 text-sm">
                Submit your credentials for on-chain verification.
              </p>
            </div>
            {error && (
              <div className="bg-red-900/30 text-red-400 p-3 rounded-lg text-sm flex items-center gap-2 border border-red-800">
                <AlertCircle className="w-4 h-4" /> {error.slice(0, 50)}...
              </div>
            )}

            <div>
              <label className="block text-sm font-semibold text-gray-200 mb-1">
                Company Name
              </label>
              <input
                required
                className="w-full px-4 py-2 border border-slate-600 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none text-white bg-slate-800 placeholder:text-gray-500"
                placeholder="e.g. Acme Industries"
                value={formData.company}
                onChange={(e) =>
                  setFormData({ ...formData, company: e.target.value })
                }
              />
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-200 mb-1">
                Business License ID
              </label>
              <input
                required
                className="w-full px-4 py-2 border border-slate-600 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none text-white bg-slate-800 placeholder:text-gray-500"
                placeholder="e.g. US-TAX-994231"
                value={formData.license}
                onChange={(e) =>
                  setFormData({ ...formData, license: e.target.value })
                }
              />
            </div>

            <div className="pt-2">
              <button
                type="submit"
                className="w-full gradient-primary text-white py-3 rounded-xl font-bold btn-glow flex items-center justify-center gap-2"
              >
                <ShieldCheck className="w-4 h-4" /> Submit Application
              </button>
              <button
                type="button"
                onClick={onClose}
                className="w-full mt-2 text-gray-400 text-sm hover:text-white font-medium transition-colors"
              >
                Cancel
              </button>
            </div>
          </form>
        )}
        {step === "verifying" && (
          <div className="text-center py-8 space-y-4">
            <div className="relative w-20 h-20 mx-auto">
              <div className="absolute inset-0 border-4 border-slate-700 rounded-full"></div>
              <div className="absolute inset-0 border-4 border-blue-500 rounded-full border-t-transparent animate-spin"></div>
            </div>
            <div>
              <h3 className="text-lg font-bold text-white">
                Verifying Credentials...
              </h3>
              <p className="text-gray-400 text-sm">
                Checking KYB Registry & License Status
              </p>
            </div>
            <div className="max-w-xs mx-auto bg-slate-800 rounded-full h-1.5 mt-4 overflow-hidden">
              <div className="h-full bg-blue-500 w-2/3"></div>
            </div>
            <p className="text-xs text-gray-500 mt-2">
              Please confirm the transaction in your wallet
            </p>
          </div>
        )}
        {step === "success" && (
          <div className="text-center py-8">
            <div className="w-20 h-20 bg-green-900/50 text-green-400 rounded-full flex items-center justify-center mx-auto mb-4 animate-bounce">
              <CheckCircle className="w-10 h-10" />
            </div>
            <h3 className="text-2xl font-bold text-white">Approved!</h3>
            <p className="text-gray-400">Access granted. Redirecting...</p>
          </div>
        )}
      </div>
    </div>
  );
};

// --- MAIN COMPONENT ---
const SupplyChainDashboard = () => {
  // --- STATE ---
  const [walletConnected, setWalletConnected] = useState<boolean>(false);
  const [account, setAccount] = useState<string>("");
  const [contract, setContract] = useState<any>(null);
  const [escrowContract, setEscrowContract] = useState<any>(null);
  const [usdcContract, setUsdcContract] = useState<any>(null);
  const [activeTab, setActiveTab] = useState<string>("shipments");
  const [userRole, setUserRole] = useState<string>("viewer");

  // Data State
  const [shipments, setShipments] = useState<any[]>([]);
  const [products, setProducts] = useState<any[]>([]);
  const [mintedMaterials, setMintedMaterials] = useState<{id: number, name: string}[]>([]);

  // Modal State
  const [showCreateModal, setShowCreateModal] = useState<boolean>(false);
  const [showJoinModal, setShowJoinModal] = useState<boolean>(false);
  const [joinRole, setJoinRole] = useState<"supplier" | "manufacturer">(
    "supplier"
  );
  const [loading, setLoading] = useState<boolean>(false);

  // --- WALLET LISTENERS ---
  useEffect(() => {
    const ethereum = (window as any).ethereum;
    if (ethereum) {
      ethereum.on("accountsChanged", (accounts: any[]) => {
        if (accounts.length > 0) connectWallet();
        else setWalletConnected(false);
      });
    }
  }, []);

  // --- CONNECT WALLET ---
  const connectWallet = async () => {
    const ethereum = (window as any).ethereum;
    if (typeof ethereum !== "undefined") {
      try {
        const provider = new ethers.BrowserProvider(ethereum);
        const accounts = await provider.send("eth_requestAccounts", []);
        const signer = await provider.getSigner();
        const address = accounts[0];

        // Initialize ALL Contracts
        const sc = new ethers.Contract(
          CONTRACT_ADDRESS,
          SUPPLY_CHAIN_ABI,
          signer
        );
        const ec = new ethers.Contract(
          PAYMENT_ESCROW_ADDRESS,
          PAYMENT_ESCROW_ABI,
          signer
        );
        const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);

        setAccount(address);
        setContract(sc);
        setEscrowContract(ec);
        setUsdcContract(usdc);
        setWalletConnected(true);

        // Check Roles (Hardcoded Admin Hash Fix)
        const ADMIN_ROLE =
          "0x0000000000000000000000000000000000000000000000000000000000000000";
        const SUPPLIER_ROLE = ethers.keccak256(
          ethers.toUtf8Bytes("SUPPLIER_ROLE")
        );
        const MANUFACTURER_ROLE = ethers.keccak256(
          ethers.toUtf8Bytes("MANUFACTURER_ROLE")
        );

        const [isAdmin, isSupplier, isManufacturer] = await Promise.all([
          sc.hasRole(ADMIN_ROLE, address),
          sc.hasRole(SUPPLIER_ROLE, address),
          sc.hasRole(MANUFACTURER_ROLE, address),
        ]);

        if (isAdmin) setUserRole("admin");
        else if (isSupplier) setUserRole("supplier");
        else if (isManufacturer) setUserRole("manufacturer");
        else setUserRole("viewer");

        // Load Data
        fetchData(sc, ec);
      } catch (error: any) {
        console.error("Failed to connect:", error);
        alert("Connection Error: " + error.message);
      }
    } else {
      alert("Please install MetaMask to use this application");
    }
  };

  // --- DATA FETCHING ---
  const fetchData = useCallback(async (scInstance: any, ecInstance: any) => {
    setLoading(true);
    try {
      const count = await scInstance.shipmentCounter();
      const loadedShipments = [];
      const loadedProducts = [];

      for (let i = 0; i < Number(count); i++) {
        // Fetch Physical Data
        const s = await scInstance.shipments(i);
        const consumed = await scInstance.shipmentConsumed(i);

        // Fetch Financial Data
        let escrowInfo = { isFunded: false, isReleased: false };
        try {
          const eDetail = await ecInstance.escrowDetails(i);
          escrowInfo = {
            isFunded: eDetail.isFunded,
            isReleased: eDetail.isReleased,
          };
        } catch (e) {
          /* Escrow might not exist yet */
        }

        const statusMap = ["CREATED", "IN_TRANSIT", "ARRIVED"];

        loadedShipments.push({
          id: i,
          status: statusMap[Number(s.status)],
          material: `Material ID: ${s.rawMaterialId}`,
          amount: s.amount.toString(),
          manufacturer: s.manufacturer,
          // If in transit, assume 65%, if arrived 100%, else 0%
          progress:
            Number(s.status) === 2 ? 100 : Number(s.status) === 1 ? 65 : 0,
          eta: new Date(
            Number(s.expectedArrivalTime) * 1000
          ).toLocaleTimeString(),
          consumed: consumed,
          escrow: escrowInfo,
          // For demo, we might need supplier address later, can use Manufacturer's escrow lookup or assume
          supplier: "0x...",
        });

        if (consumed) {
          loadedProducts.push({
            id: i + 100,
            name: `Product Batch #${i}`,
            shipmentId: i,
            rawMaterial: `Mat-${s.rawMaterialId}`,
            timestamp: new Date().toLocaleDateString(),
          });
        }
      }
      setShipments(loadedShipments.reverse());
      setProducts(loadedProducts);
    } catch (e) {
      console.error("Fetch error:", e);
    }
    setLoading(false);
  }, []);

  // --- ACTIONS ---

  const handleFundEscrow = async (shipmentId: any, supplierAddr: any) => {
    try {
      const amountToFund = prompt("Enter USDC Amount to Fund:", "1000");
      if (!amountToFund) return;
      const weiAmount = ethers.parseUnits(amountToFund, 18); // Assume 18 decimals

      const approveTx = await usdcContract.approve(
        PAYMENT_ESCROW_ADDRESS,
        weiAmount
      );
      await approveTx.wait();

      const finalSupplier =
        !supplierAddr ||
        supplierAddr === "0x..." ||
        supplierAddr === ethers.ZeroAddress
          ? prompt("Enter Supplier Address:")
          : supplierAddr;

      const fundTx = await escrowContract.createEscrow(
        shipmentId,
        finalSupplier,
        weiAmount
      );
      await fundTx.wait();

      alert("Escrow Funded Successfully!");
      fetchData(contract, escrowContract);
    } catch (e: any) {
      alert("Funding Failed: " + e.message);
    }
  };

  const handleReleasePayment = async (shipmentId: any) => {
    try {
      const tx = await escrowContract.releasePayment(shipmentId);
      await tx.wait();
      alert("Payment Released to Supplier!");
      fetchData(contract, escrowContract);
    } catch (e: any) {
      alert("Release Failed: " + e.message);
    }
  };

  const handleStartDelivery = async (id: any) => {
    try {
      const tx = await contract.startDelivery(id);
      await tx.wait();
      fetchData(contract, escrowContract);
    } catch (e: any) {
      alert("Error: " + e.message);
    }
  };

  // ADDED: Force Arrival Handler
  const handleForceArrival = async (id: any) => {
    try {
      const tx = await contract.manufacturerForceArrival(id);
      await tx.wait();
      fetchData(contract, escrowContract); // Refreshes the UI
    } catch (e: any) {
      alert("Error: " + (e.reason || e.message));
    }
  };

  const handleAssemble = async (id: any, amt: any) => {
    try {
      const uris = Array(Number(amt)).fill("ipfs://metadata");
      const tx = await contract.assembleProduct(id, uris);
      await tx.wait();
      fetchData(contract, escrowContract);
    } catch (e: any) {
      alert("Error: " + e.message);
    }
  };

  // --- ERROR HANDLING ---
  const parseContractError = (error: any): string => {
    const message = error?.message || error?.toString() || "Unknown error";
    
    // Common contract error patterns
    if (message.includes("insufficient") || message.includes("balance")) {
      return "Insufficient balance. Make sure you have enough materials minted.";
    }
    if (message.includes("not authorized") || message.includes("AccessControl")) {
      return "You don't have permission to perform this action.";
    }
    if (message.includes("user rejected") || message.includes("User denied")) {
      return "Transaction cancelled by user.";
    }
    if (message.includes("invalid address") || message.includes("INVALID_ARGUMENT")) {
      return "Invalid address format. Please check the wallet address.";
    }
    if (message.includes("execution reverted")) {
      // Try to extract revert reason
      if (message.includes("ERC1155")) {
        return "Token error: You may not have enough of this material.";
      }
      return "Transaction failed. The contract rejected this operation.";
    }
    if (message.includes("network") || message.includes("RPC")) {
      return "Network error. Please check your connection and try again.";
    }
    
    // Truncate long error messages
    if (message.length > 100) {
      return message.substring(0, 100) + "...";
    }
    
    return message;
  };

  const handleMint = async (e: any) => {
    e.preventDefault();
    const fd = new FormData(e.target);
    const materialName = fd.get("id") as string;
    const amount = fd.get("amount") as string;
    
    if (!materialName.trim()) {
      alert("Please enter a material name.");
      return;
    }
    if (!amount || parseInt(amount) <= 0) {
      alert("Please enter a valid quantity greater than 0.");
      return;
    }
    
    // Generate next material ID (1-based)
    const nextId = mintedMaterials.length > 0 
      ? Math.max(...mintedMaterials.map(m => m.id)) + 1 
      : 1;
    
    try {
      const tx = await contract.mint(
        account,
        nextId, // Pass numeric ID to contract
        amount,
        "0x"
      );
      await tx.wait();
      // Add to minted materials with name and ID
      if (materialName && !mintedMaterials.some(m => m.name === materialName)) {
        setMintedMaterials(prev => [...prev, { id: nextId, name: materialName }]);
      }
      alert(`✅ Successfully minted ${amount} units of "${materialName}" (ID: ${nextId})!`);
      e.target.reset();
    } catch (error: any) {
      alert("❌ Minting failed: " + parseContractError(error));
    }
  };

  const handleGrant = async (roleType: any, addr: any) => {
    if (!addr || !addr.startsWith("0x") || addr.length !== 42) {
      alert("❌ Please enter a valid Ethereum address (0x... format, 42 characters).");
      return;
    }
    
    try {
      const role =
        roleType === "supplier"
          ? ethers.keccak256(ethers.toUtf8Bytes("SUPPLIER_ROLE"))
          : ethers.keccak256(ethers.toUtf8Bytes("MANUFACTURER_ROLE"));
      const tx = await contract.grantRole(role, addr);
      await tx.wait();
      alert(`✅ Successfully granted ${roleType} role to ${addr.slice(0, 6)}...${addr.slice(-4)}!`);
    } catch (error: any) {
      alert("❌ Grant failed: " + parseContractError(error));
    }
  };

  const handleCreate = async (formData: any) => {
    // Validation
    if (!formData.manufacturer || !formData.manufacturer.startsWith("0x")) {
      alert("❌ Please enter a valid manufacturer address (0x... format).");
      return;
    }
    if (!formData.rawMaterialId) {
      alert("❌ Please select a material. You need to mint materials first.");
      return;
    }
    if (!formData.amount || parseInt(formData.amount) <= 0) {
      alert("❌ Please enter a valid amount greater than 0.");
      return;
    }
    
    try {
      const tx = await contract.createShipment(
        parseInt(formData.destLat) || 0,
        parseInt(formData.destLong) || 0,
        parseInt(formData.radius) || 1000,
        formData.manufacturer,
        parseInt(formData.rawMaterialId),
        parseInt(formData.amount),
        Math.floor(Date.now() / 1000) + parseInt(formData.eta || "24") * 3600
      );
      await tx.wait();
      setShowCreateModal(false);
      alert("✅ Shipment created successfully!");
      fetchData(contract, escrowContract);
    } catch (error: any) {
      alert("❌ Shipment creation failed: " + parseContractError(error));
    }
  };

  const openJoinModal = (role: "supplier" | "manufacturer") => {
    setJoinRole(role);
    setShowJoinModal(true);
  };

  const executeJoin = async () => {
    if (!contract) return;
    let tx;
    if (joinRole === "supplier") {
      tx = await contract.demoJoinAsSupplier();
    } else {
      tx = await contract.demoJoinAsManufacturer();
    }
    await tx.wait();
  };

  // --- HELPERS ---
  const getStatusColor = (status: any) => {
    switch (status) {
      case "CREATED":
        return "bg-blue-500";
      case "IN_TRANSIT":
        return "bg-yellow-500";
      case "ARRIVED":
        return "bg-green-500";
      default:
        return "bg-gray-500";
    }
  };

  const getStatusIcon = (status: any) => {
    switch (status) {
      case "CREATED":
        return <Package className="w-5 h-5" />;
      case "IN_TRANSIT":
        return <Truck className="w-5 h-5" />;
      case "ARRIVED":
        return <CheckCircle className="w-5 h-5" />;
      default:
        return <Clock className="w-5 h-5" />;
    }
  };

  // --- SHIPMENT CREATE MODAL ---
  const CreateShipmentModal = ({ onClose, materials }: { onClose: any; materials: {id: number, name: string}[] }) => {
    const [formData, setFormData] = useState<any>({
      destLat: "",
      destLong: "",
      radius: "1000",
      manufacturer: "",
      rawMaterialId: materials.length > 0 ? materials[0].id.toString() : "",
      amount: "",
      eta: "24",
    });

    return (
      <div className="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50 p-4">
        <div className="bg-slate-900 rounded-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto shadow-2xl animate-slide-up border border-slate-700">
          <div className="p-6 border-b border-slate-700">
            <h2 className="text-2xl font-bold text-white">
              Create New Shipment
            </h2>
          </div>
          <div className="p-6 space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-semibold text-gray-200 mb-2">
                  Latitude (×10⁶)
                </label>
                <input
                  type="text"
                  className="w-full px-4 py-2 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  placeholder="e.g. 40712776"
                  value={formData.destLat}
                  onChange={(e) =>
                    setFormData({ ...formData, destLat: e.target.value })
                  }
                />
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-200 mb-2">
                  Longitude (×10⁶)
                </label>
                <input
                  type="text"
                  className="w-full px-4 py-2 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  placeholder="e.g. -74005974"
                  value={formData.destLong}
                  onChange={(e) =>
                    setFormData({ ...formData, destLong: e.target.value })
                  }
                />
              </div>
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-200 mb-2">
                Manufacturer Address
              </label>
              <input
                type="text"
                className="w-full px-4 py-2 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                placeholder="0x..."
                value={formData.manufacturer}
                onChange={(e) =>
                  setFormData({ ...formData, manufacturer: e.target.value })
                }
              />
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-semibold text-gray-200 mb-2">
                  Material
                </label>
                {materials.length === 0 ? (
                  <div className="w-full px-4 py-2 border border-slate-600 rounded-lg text-gray-400 bg-slate-800">
                    No materials minted yet
                  </div>
                ) : (
                  <select
                    className="w-full px-4 py-2 border border-slate-600 rounded-lg text-white bg-slate-800 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                    value={formData.rawMaterialId}
                    onChange={(e) =>
                      setFormData({ ...formData, rawMaterialId: e.target.value })
                    }
                  >
                    {materials.map((material) => (
                      <option key={material.id} value={material.id}>
                        {material.name}
                      </option>
                    ))}
                  </select>
                )}
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-200 mb-2">
                  Amount
                </label>
                <input
                  type="number"
                  className="w-full px-4 py-2 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  placeholder="100"
                  value={formData.amount}
                  onChange={(e) =>
                    setFormData({ ...formData, amount: e.target.value })
                  }
                />
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-200 mb-2">
                  ETA (Hours)
                </label>
                <input
                  type="number"
                  className="w-full px-4 py-2 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  value={formData.eta}
                  onChange={(e) =>
                    setFormData({ ...formData, eta: e.target.value })
                  }
                />
              </div>
            </div>
            <div>
              <label className="block text-sm font-semibold text-gray-200 mb-2">
                Radius (meters)
              </label>
              <input
                type="number"
                className="w-full px-4 py-2 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                value={formData.radius}
                onChange={(e) =>
                  setFormData({ ...formData, radius: e.target.value })
                }
              />
            </div>
          </div>
          <div className="p-6 border-t border-slate-700 flex gap-3">
            <button
              onClick={onClose}
              className="flex-1 px-6 py-3 border border-slate-600 text-gray-300 rounded-lg font-medium hover:bg-slate-800 transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={() => handleCreate(formData)}
              className="flex-1 px-6 py-3 gradient-primary text-white rounded-lg font-medium btn-glow"
            >
              Create Shipment
            </button>
          </div>
        </div>
      </div>
    );
  };

  // --- 1. LANDING PAGE ---
  if (!walletConnected) {
    return (
      <div className="min-h-screen gradient-bg animate-gradient flex items-center justify-center p-4 relative overflow-hidden">
        {/* Decorative background elements */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <div className="absolute -top-40 -right-40 w-80 h-80 bg-blue-400/20 rounded-full blur-3xl" />
          <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-purple-400/20 rounded-full blur-3xl" />
        </div>
        
        <div className="max-w-md w-full relative z-10">
          <div className="glass rounded-3xl p-8 text-center space-y-6 animate-slide-up">
            <div className="w-20 h-20 gradient-primary rounded-2xl mx-auto flex items-center justify-center animate-float shadow-lg">
              <Truck className="w-10 h-10 text-white" />
            </div>
            <div>
              <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-2">
                RWA Supply Chain
              </h1>
              <p className="text-gray-600 dark:text-gray-300">
                Real World Assets Tracking Platform
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-2 inline-flex items-center gap-1.5 px-2 py-1 bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 rounded-full">
                <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
                Stagenet Live
              </p>
            </div>
            <button
              onClick={connectWallet}
              className="w-full gradient-primary text-white py-4 rounded-xl font-semibold btn-glow flex items-center justify-center gap-2 animate-pulse-glow"
            >
              <Wallet className="w-5 h-5" /> Connect Wallet
            </button>
            <p className="text-xs text-gray-400 dark:text-gray-500">
              Connect your wallet to access the supply chain dashboard
            </p>
          </div>
        </div>
      </div>
    );
  }

  // --- 2. DASHBOARD ---
  return (
    <div className="min-h-screen gradient-bg relative">
      {/* Decorative background elements */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-0 right-0 w-96 h-96 bg-blue-400/10 rounded-full blur-3xl" />
        <div className="absolute bottom-0 left-0 w-96 h-96 bg-purple-400/10 rounded-full blur-3xl" />
      </div>
      
      <header className="glass sticky top-0 z-40 border-b border-white/10 dark:border-white/5">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 gradient-primary rounded-xl flex items-center justify-center shadow-lg">
                <Truck className="w-6 h-6 text-white" />
              </div>
              <div>
                <h1 className="text-xl font-bold text-gray-900 dark:text-white">
                  RWA Supply Chain
                </h1>
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  Blockchain-powered logistics
                </p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <div className="hidden sm:block px-4 py-2 glass-subtle rounded-lg">
                <p className="text-xs text-gray-500 dark:text-gray-400">Connected</p>
                <p className="font-mono text-sm font-semibold text-gray-900 dark:text-white">
                  {account.slice(0, 6)}...{account.slice(-4)}
                </p>
              </div>
              <div
                className={`px-3 py-2 rounded-lg text-sm font-medium capitalize transition-all ${
                  userRole === "admin"
                    ? "bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300"
                    : userRole === "supplier"
                    ? "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300"
                    : userRole === "manufacturer"
                    ? "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300"
                    : "bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300"
                }`}
              >
                {userRole}
              </div>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 relative z-10">
        {userRole === "viewer" ? (
          <div className="max-w-4xl mx-auto px-4 py-12">
            <div className="glass rounded-3xl p-8 text-center animate-slide-up">
              <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                Join the Protocol
              </h2>
              <p className="text-gray-500 dark:text-gray-400 mb-8 max-w-lg mx-auto">
                To participate in the supply chain, you must apply for a
                verified role. Please submit your business credentials below.
              </p>
              <div className="flex flex-col sm:flex-row gap-4 justify-center">
                <button
                  onClick={() => openJoinModal("supplier")}
                  className="flex flex-col items-center p-6 border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-xl hover:border-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/20 transition-all w-full sm:w-64 group"
                >
                  <div className="w-12 h-12 bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 rounded-full flex items-center justify-center mb-3 group-hover:scale-110 transition-transform">
                    <Database className="w-6 h-6" />
                  </div>
                  <span className="font-bold text-gray-900 dark:text-white">
                    Apply as Supplier
                  </span>
                  <span className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    Mint & Ship Raw Materials
                  </span>
                </button>
                <button
                  onClick={() => openJoinModal("manufacturer")}
                  className="flex flex-col items-center p-6 border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-xl hover:border-green-500 hover:bg-green-50 dark:hover:bg-green-900/20 transition-all w-full sm:w-64 group"
                >
                  <div className="w-12 h-12 bg-green-100 dark:bg-green-900/30 text-green-600 dark:text-green-400 rounded-full flex items-center justify-center mb-3 group-hover:scale-110 transition-transform">
                    <Factory className="w-6 h-6" />
                  </div>
                  <span className="font-bold text-gray-900 dark:text-white">
                    Apply as Manufacturer
                  </span>
                  <span className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    Receive & Assemble Goods
                  </span>
                </button>
              </div>
            </div>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
              <div className="glass rounded-2xl p-6 hover-lift animate-fade-in" style={{ animationDelay: '0ms' }}>
                <div className="flex items-center justify-between mb-4">
                  <div className="w-12 h-12 bg-blue-100 dark:bg-blue-900/30 rounded-xl flex items-center justify-center">
                    <Package className="w-6 h-6 text-blue-600 dark:text-blue-400" />
                  </div>
                  <span className="text-2xl font-bold text-gray-900 dark:text-white">
                    {
                      shipments.filter((s: any) => s.status === "CREATED")
                        .length
                    }
                  </span>
                </div>
                <h3 className="text-gray-600 dark:text-gray-300 font-medium">Pending Shipments</h3>
              </div>
              <div className="glass rounded-2xl p-6 hover-lift animate-fade-in" style={{ animationDelay: '100ms' }}>
                <div className="flex items-center justify-between mb-4">
                  <div className="w-12 h-12 bg-yellow-100 dark:bg-yellow-900/30 rounded-xl flex items-center justify-center">
                    <Truck className="w-6 h-6 text-yellow-600 dark:text-yellow-400" />
                  </div>
                  <span className="text-2xl font-bold text-gray-900 dark:text-white">
                    {
                      shipments.filter((s: any) => s.status === "IN_TRANSIT")
                        .length
                    }
                  </span>
                </div>
                <h3 className="text-gray-600 dark:text-gray-300 font-medium">In Transit</h3>
              </div>
              <div className="glass rounded-2xl p-6 hover-lift animate-fade-in" style={{ animationDelay: '200ms' }}>
                <div className="flex items-center justify-between mb-4">
                  <div className="w-12 h-12 bg-green-100 dark:bg-green-900/30 rounded-xl flex items-center justify-center">
                    <CheckCircle className="w-6 h-6 text-green-600 dark:text-green-400" />
                  </div>
                  <span className="text-2xl font-bold text-gray-900 dark:text-white">
                    {
                      shipments.filter((s: any) => s.status === "ARRIVED")
                        .length
                    }
                  </span>
                </div>
                <h3 className="text-gray-600 dark:text-gray-300 font-medium">Delivered</h3>
              </div>
            </div>

            <div className="glass rounded-2xl mb-6">
              <div className="border-b border-gray-200/50 dark:border-gray-700/50 px-6">
                <div className="flex gap-8 overflow-x-auto">
                  {["shipments", "products", "supplier", "admin"].map((tab) =>
                    (tab === "admin" && userRole !== "admin") ||
                    (tab === "supplier" && userRole !== "supplier") ? null : (
                      <button
                        key={tab}
                        onClick={() => setActiveTab(tab)}
                        className={`py-4 border-b-2 font-medium transition-all capitalize min-w-max ${
                          activeTab === tab
                            ? "border-blue-600 text-blue-600 dark:text-blue-400"
                            : "border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
                        }`}
                      >
                        {tab}
                      </button>
                    )
                  )}
                </div>
              </div>

              <div className="p-6">
                {activeTab === "shipments" && (
                  <>
                    <div className="flex justify-between items-center mb-6">
                      <h2 className="text-xl font-bold text-gray-900 dark:text-white">
                        Active Shipments
                      </h2>
                      {userRole === "supplier" && (
                        <button
                          onClick={() => setShowCreateModal(true)}
                          className="flex items-center gap-2 px-4 py-2 gradient-primary text-white rounded-lg font-medium btn-glow"
                        >
                          <Plus className="w-4 h-4" /> Create Shipment
                        </button>
                      )}
                    </div>
                    {loading ? (
                      <div className="text-center py-12">
                        <div className="inline-block animate-spin rounded-full h-10 w-10 border-2 border-blue-600 border-t-transparent"></div>
                        <p className="text-gray-500 dark:text-gray-400 mt-3">Loading shipments...</p>
                      </div>
                    ) : shipments.length === 0 ? (
                      <div className="text-center py-12">
                        <div className="w-16 h-16 bg-gray-100 dark:bg-gray-800 rounded-full flex items-center justify-center mx-auto mb-4">
                          <Package className="w-8 h-8 text-gray-400 dark:text-gray-500" />
                        </div>
                        <p className="text-gray-600 dark:text-gray-400">No shipments found</p>
                        <p className="text-gray-400 dark:text-gray-500 text-sm mt-1">Create a new shipment to get started</p>
                      </div>
                    ) : (
                      <div className="space-y-4">
                        {shipments.map((shipment: any, index: number) => (
                          <div
                            key={shipment.id}
                            className="glass-subtle border border-gray-200/50 dark:border-gray-700/50 rounded-xl p-6 hover-lift animate-fade-in"
                            style={{ animationDelay: `${index * 50}ms` }}
                          >
                            <div className="flex items-start justify-between mb-4">
                              <div className="flex items-center gap-4">
                                <div
                                  className={`w-12 h-12 ${getStatusColor(
                                    shipment.status
                                  )} rounded-xl flex items-center justify-center text-white shadow-lg`}
                                >
                                  {getStatusIcon(shipment.status)}
                                </div>
                                <div>
                                  <h3 className="font-bold text-gray-900 dark:text-white text-lg">
                                    Shipment #{shipment.id}
                                  </h3>
                                  <p className="text-gray-600 dark:text-gray-400">
                                    {shipment.material} • {shipment.amount}{" "}
                                    units
                                  </p>
                                </div>
                              </div>
                              <div className="flex flex-col items-end gap-2">
                                <span
                                  className={`px-3 py-1 rounded-full text-xs font-medium transition-all ${
                                    shipment.status === "ARRIVED"
                                      ? "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
                                      : shipment.status === "IN_TRANSIT"
                                      ? "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"
                                      : "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
                                  }`}
                                >
                                  {shipment.status.replace("_", " ")}
                                </span>
                                {shipment.escrow.isFunded &&
                                  !shipment.escrow.isReleased && (
                                    <span className="flex items-center gap-1 text-xs font-bold text-blue-600 bg-blue-50 px-2 py-1 rounded">
                                      <Coins className="w-3 h-3" /> Funded
                                    </span>
                                  )}
                                {shipment.escrow.isReleased && (
                                  <span className="flex items-center gap-1 text-xs font-bold text-green-600 bg-green-50 px-2 py-1 rounded">
                                    <CheckCircle className="w-3 h-3" /> Paid
                                  </span>
                                )}
                              </div>
                            </div>

                            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
                              <div>
                                <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">
                                  Manufacturer
                                </p>
                                <p className="font-mono text-sm font-medium text-gray-900 dark:text-white">
                                  {shipment.manufacturer
                                    ? `${shipment.manufacturer.slice(0, 12)}...`
                                    : "Not set"}
                                </p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">
                                  ETA
                                </p>
                                <p className="text-sm font-medium text-gray-900 dark:text-white flex items-center gap-1">
                                  <Clock className="w-4 h-4" /> {shipment.eta}
                                </p>
                              </div>
                              <div>
                                <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">
                                  Progress
                                </p>
                                <p className="text-sm font-medium text-gray-900 dark:text-white">
                                  {shipment.progress}%
                                </p>
                              </div>
                            </div>

                            {shipment.status === "IN_TRANSIT" && (
                              <div className="mb-4">
                                <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2 overflow-hidden">
                                  <div
                                    className="gradient-primary h-2 rounded-full transition-all duration-500 animate-progress-pulse"
                                    style={{ width: `${shipment.progress}%` }}
                                  />
                                </div>
                              </div>
                            )}

                            <div className="flex flex-wrap gap-2">
                              <button className="flex-1 px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 flex items-center justify-center gap-2 transition-colors">
                                <MapPin className="w-4 h-4" /> Track
                              </button>

                              {/* SUPPLIER ACTIONS */}
                              {shipment.status === "CREATED" &&
                                userRole === "supplier" && (
                                  <button
                                    onClick={() =>
                                      handleStartDelivery(shipment.id)
                                    }
                                    className="flex-1 px-4 py-2 gradient-primary text-white rounded-lg font-medium btn-glow flex items-center justify-center gap-2"
                                  >
                                    <Send className="w-4 h-4" /> Start Delivery
                                  </button>
                                )}

                              {/* MANUFACTURER ACTIONS */}
                              {shipment.status === "IN_TRANSIT" &&
                                userRole === "manufacturer" && (
                                  <button
                                    onClick={() =>
                                      handleForceArrival(shipment.id)
                                    }
                                    className="flex-1 px-4 py-2 bg-orange-500 hover:bg-orange-600 text-white rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
                                  >
                                    <CheckCircle className="w-4 h-4" /> Force Arrival
                                  </button>
                                )}

                              {shipment.status === "ARRIVED" &&
                                userRole === "manufacturer" &&
                                !shipment.consumed && (
                                  <button
                                    onClick={() =>
                                      handleAssemble(
                                        shipment.id,
                                        shipment.amount
                                      )
                                    }
                                    className="flex-1 px-4 py-2 bg-green-500 hover:bg-green-600 text-white rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
                                  >
                                    <Factory className="w-4 h-4" /> Assemble
                                  </button>
                                )}

                              {/* PAYMENT ACTIONS */}
                              {shipment.status === "CREATED" &&
                                userRole === "manufacturer" &&
                                !shipment.escrow.isFunded && (
                                  <button
                                    onClick={() =>
                                      handleFundEscrow(
                                        shipment.id,
                                        shipment.supplier
                                      )
                                    }
                                    className="flex-1 px-4 py-2 bg-purple-500 hover:bg-purple-600 text-white rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
                                  >
                                    <Coins className="w-4 h-4" /> Fund Escrow
                                  </button>
                                )}
                              {shipment.status === "ARRIVED" &&
                                userRole === "manufacturer" &&
                                shipment.escrow.isFunded &&
                                !shipment.escrow.isReleased && (
                                  <button
                                    onClick={() =>
                                      handleReleasePayment(shipment.id)
                                    }
                                    className="flex-1 px-4 py-2 bg-indigo-500 hover:bg-indigo-600 text-white rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
                                  >
                                    <DollarSign className="w-4 h-4" /> Release Payment
                                  </button>
                                )}
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}
                {/* PRODUCTS TAB */}
                {activeTab === "products" && (
                  <>
                    <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-6">
                      Manufactured Products
                    </h2>
                    {products.length === 0 ? (
                      <div className="text-center py-12">
                        <div className="w-16 h-16 bg-gray-100 dark:bg-gray-800 rounded-full flex items-center justify-center mx-auto mb-4">
                          <Box className="w-8 h-8 text-gray-400 dark:text-gray-500" />
                        </div>
                        <p className="text-gray-600 dark:text-gray-400">No products yet</p>
                        <p className="text-gray-400 dark:text-gray-500 text-sm mt-1">Manufactured products will appear here</p>
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                        {products.map((product: any, index: number) => (
                          <div
                            key={product.id}
                            className="glass-subtle border border-gray-200/50 dark:border-gray-700/50 rounded-xl p-6 hover-lift animate-fade-in"
                            style={{ animationDelay: `${index * 50}ms` }}
                          >
                            <div className="flex items-start gap-4 mb-4">
                              <div className="w-12 h-12 bg-purple-100 dark:bg-purple-900/30 rounded-xl flex items-center justify-center">
                                <Box className="w-6 h-6 text-purple-600 dark:text-purple-400" />
                              </div>
                              <div>
                                <h3 className="font-bold text-gray-900 dark:text-white">
                                  {product.name}
                                </h3>
                                <p className="text-sm text-gray-600 dark:text-gray-400">
                                  ID: {product.id}
                                </p>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}
                {/* SUPPLIER TAB */}
                {activeTab === "supplier" && (
                  <div className="max-w-xl mx-auto space-y-6">
                    <h3 className="text-xl font-bold flex items-center gap-2 text-gray-900 dark:text-white">
                      <Database className="text-blue-500" /> Mint Raw Materials
                    </h3>
                    <form onSubmit={handleMint} className="space-y-4">
                      <div>
                        <label className="block text-sm font-medium text-gray-300 mb-2">
                          Material Name
                        </label>
                        <input
                          name="id"
                          type="text"
                          className="w-full px-4 py-3 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 transition-all"
                          required
                          placeholder="e.g. Steel, Copper, Gold, Lithium..."
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-300 mb-2">
                          Quantity
                        </label>
                        <input
                          name="amount"
                          type="number"
                          className="w-full px-4 py-3 border border-slate-600 rounded-lg text-white bg-slate-800 placeholder:text-gray-500 focus:ring-2 focus:ring-blue-500 transition-all"
                          required
                          placeholder="Enter quantity"
                        />
                      </div>
                      <button
                        type="submit"
                        className="w-full gradient-primary text-white py-3 rounded-lg font-bold btn-glow"
                      >
                        Mint Tokens
                      </button>
                    </form>
                  </div>
                )}
                {/* ADMIN TAB */}
                {activeTab === "admin" && (
                  <div className="max-w-xl mx-auto space-y-6">
                    <h3 className="text-xl font-bold flex items-center gap-2 text-gray-900 dark:text-white">
                      <Users className="text-purple-500" /> Grant Permissions
                    </h3>
                    <div className="space-y-4">
                      <input
                        id="grantInput"
                        placeholder="Wallet Address (0x...)"
                        className="w-full px-4 py-3 border border-gray-300 dark:border-gray-600 rounded-lg text-gray-900 dark:text-white bg-white dark:bg-gray-800 focus:ring-2 focus:ring-blue-500 transition-all"
                      />
                      <div className="flex gap-4">
                        <button
                          onClick={() =>
                            handleGrant(
                              "supplier",
                              (
                                document.getElementById(
                                  "grantInput"
                                ) as HTMLInputElement
                              ).value
                            )
                          }
                          className="flex-1 bg-slate-800 dark:bg-slate-700 hover:bg-slate-900 dark:hover:bg-slate-600 text-white py-3 rounded-lg font-bold transition-colors"
                        >
                          Grant Supplier
                        </button>
                        <button
                          onClick={() =>
                            handleGrant(
                              "manufacturer",
                              (
                                document.getElementById(
                                  "grantInput"
                                ) as HTMLInputElement
                              ).value
                            )
                          }
                          className="flex-1 gradient-primary text-white py-3 rounded-lg font-bold btn-glow"
                        >
                          Grant Manufacturer
                        </button>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </>
        )}
      </main>
      {showCreateModal && (
        <CreateShipmentModal onClose={() => setShowCreateModal(false)} materials={mintedMaterials} />
      )}
      {showJoinModal && (
        <JoinNetworkModal
          roleType={joinRole}
          onClose={() => setShowJoinModal(false)}
          onConfirm={executeJoin}
        />
      )}
      <footer className="mt-12 border-t border-gray-200/50 dark:border-gray-700/50 relative z-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex flex-col md:flex-row justify-between items-center">
            <div className="flex items-center gap-3 mb-4 md:mb-0">
              <div className="w-8 h-8 gradient-primary rounded-lg flex items-center justify-center shadow-lg">
                <ShieldCheck className="w-4 h-4 text-white" />
              </div>
              <div>
                <p className="text-sm font-medium text-gray-900 dark:text-white">
                  RWA Supply Chain
                </p>
                <p className="text-xs text-gray-600 dark:text-gray-400 flex items-center gap-1">
                  <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
                  Contracts Active
                </p>
              </div>
            </div>
            <div className="text-xs text-gray-500 dark:text-gray-400 font-mono bg-gray-100 dark:bg-gray-800 px-3 py-2 rounded-lg">
              SupplyChain: {CONTRACT_ADDRESS.slice(0, 6)}...{CONTRACT_ADDRESS.slice(-4)} | NFT:{" "}
              {PRODUCT_NFT_ADDRESS.slice(0, 6)}...{PRODUCT_NFT_ADDRESS.slice(-4)}
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
};

export default SupplyChainDashboard;
