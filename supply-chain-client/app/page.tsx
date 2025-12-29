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
// IMPORTANT: Update these with your LATEST deployment addresses from the terminal
const CONTRACT_ADDRESS = "0xED8762e66E24a48Dcc3E024c029EfFEFaB55bBEf"; // SupplyChainRWA
const PAYMENT_ESCROW_ADDRESS = "0x1F4196535122288dd345EA6eeCDAa9bb86AE0356"; // Escrow
const PRODUCT_NFT_ADDRESS = "0xe178729D689320081C46801Ae09269E0566f435b"; // ProductNFT
const USDC_ADDRESS = "0x7a5329F720e4a37893e44B0fFD491f11bdB855CA"; // MockUSDC

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
  "function createShipment(int256 destLat, int256 destLong, uint256 radius, address manufacturer, uint256 rawMaterialId, uint256 amount, uint256 expectedArrivalTime)",
  "function startDelivery(uint256 shipmentId)",
  "function assembleProduct(uint256 shipmentId, string[] metadataURIs)",
  "function balanceOf(address account, uint256 id) view returns (uint256)",
  // --- Demo / Hackathon Functions ---
  "function demoJoinAsSupplier()",
  "function demoJoinAsManufacturer()",
  // --- Force Arrival ---
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
      <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl relative overflow-hidden">
        {step === "form" && (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="text-center mb-6">
              <div
                className={`w-16 h-16 mx-auto rounded-full flex items-center justify-center mb-4 ${roleType === "supplier"
                  ? "bg-blue-100 text-blue-600"
                  : "bg-green-100 text-green-600"
                  }`}
              >
                {roleType === "supplier" ? (
                  <Database className="w-8 h-8" />
                ) : (
                  <Factory className="w-8 h-8" />
                )}
              </div>
              <h2 className="text-2xl font-bold text-gray-900 capitalize">
                Join as {roleType}
              </h2>
              <p className="text-gray-500 text-sm">
                Submit your credentials for on-chain verification.
              </p>
            </div>
            {error && (
              <div className="bg-red-50 text-red-600 p-3 rounded-lg text-sm flex items-center gap-2">
                <AlertCircle className="w-4 h-4" /> {error.slice(0, 50)}...
              </div>
            )}

            {/* Form Inputs */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Company Name
              </label>
              <input
                required
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none text-gray-900 bg-white"
                placeholder="e.g. Acme Industries"
                value={formData.company}
                onChange={(e) =>
                  setFormData({ ...formData, company: e.target.value })
                }
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Business License ID
              </label>
              <input
                required
                className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none text-gray-900 bg-white"
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
                className="w-full bg-slate-900 text-white py-3 rounded-xl font-bold hover:bg-slate-800 transition-all flex items-center justify-center gap-2"
              >
                <ShieldCheck className="w-4 h-4" /> Submit Application
              </button>
              <button
                type="button"
                onClick={onClose}
                className="w-full mt-2 text-gray-500 text-sm hover:text-gray-800"
              >
                Cancel
              </button>
            </div>
          </form>
        )}
        {step === "verifying" && (
          <div className="text-center py-8 space-y-4">
            <div className="relative w-20 h-20 mx-auto">
              <div className="absolute inset-0 border-4 border-gray-200 rounded-full"></div>
              <div className="absolute inset-0 border-4 border-blue-600 rounded-full border-t-transparent animate-spin"></div>
            </div>
            <div>
              <h3 className="text-lg font-bold text-gray-900">
                Verifying Credentials...
              </h3>
              <p className="text-gray-500 text-sm">
                Checking KYB Registry & License Status
              </p>
            </div>
            <div className="max-w-xs mx-auto bg-gray-100 rounded-full h-1.5 mt-4 overflow-hidden">
              <div className="h-full bg-blue-600 w-2/3"></div>
            </div>
            <p className="text-xs text-gray-400 mt-2">
              Please confirm the transaction in your wallet
            </p>
          </div>
        )}
        {step === "success" && (
          <div className="text-center py-8">
            <div className="w-20 h-20 bg-green-100 text-green-600 rounded-full flex items-center justify-center mx-auto mb-4 animate-bounce">
              <CheckCircle className="w-10 h-10" />
            </div>
            <h3 className="text-2xl font-bold text-gray-900">Approved!</h3>
            <p className="text-gray-500">Access granted. Redirecting...</p>
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
        const sc = new ethers.Contract(CONTRACT_ADDRESS, SUPPLY_CHAIN_ABI, signer);
        const ec = new ethers.Contract(PAYMENT_ESCROW_ADDRESS, PAYMENT_ESCROW_ABI, signer);
        const usdc = new ethers.Contract(USDC_ADDRESS, ERC20_ABI, signer);

        setAccount(address);
        setContract(sc);
        setEscrowContract(ec);
        setUsdcContract(usdc);
        setWalletConnected(true);

        // Check Roles
        const ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000";
        const SUPPLIER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("SUPPLIER_ROLE"));
        const MANUFACTURER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MANUFACTURER_ROLE"));

        const [isAdmin, isSupplier, isManufacturer] = await Promise.all([
          sc.hasRole(ADMIN_ROLE, address),
          sc.hasRole(SUPPLIER_ROLE, address),
          sc.hasRole(MANUFACTURER_ROLE, address),
        ]);

        if (isAdmin) setUserRole("admin");
        else if (isSupplier) setUserRole("supplier");
        else if (isManufacturer) setUserRole("manufacturer");
        else setUserRole("viewer");

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
        } catch (e) { /* Escrow might not exist yet */ }

        const statusMap = ["CREATED", "IN_TRANSIT", "ARRIVED"];

        loadedShipments.push({
          id: i,
          status: statusMap[Number(s.status)],
          material: `Material ID: ${s.rawMaterialId}`,
          amount: s.amount.toString(),
          manufacturer: s.manufacturer,
          progress: Number(s.status) === 2 ? 100 : Number(s.status) === 1 ? 65 : 0,
          eta: new Date(Number(s.expectedArrivalTime) * 1000).toLocaleTimeString(),
          consumed: consumed,
          escrow: escrowInfo,
          supplier: "0x...", // Can be updated if tracked in events
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
      const weiAmount = ethers.parseUnits(amountToFund, 18);

      // 1. Approve USDC
      const approveTx = await usdcContract.approve(PAYMENT_ESCROW_ADDRESS, weiAmount);
      await approveTx.wait();

      // 2. Create Escrow
      const finalSupplier = !supplierAddr || supplierAddr === "0x..." || supplierAddr === ethers.ZeroAddress
        ? prompt("Enter Supplier Address:")
        : supplierAddr;

      const fundTx = await escrowContract.createEscrow(shipmentId, finalSupplier, weiAmount);
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
      fetchData(contract, escrowContract);
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

  const handleMint = async (e: any) => {
    e.preventDefault();
    const fd = new FormData(e.target);
    try {
      const tx = await contract.mint(account, fd.get("id"), fd.get("amount"), "0x");
      await tx.wait();
      alert("Minted!");
    } catch (e: any) {
      alert("Error: " + e.message);
    }
  };

  const handleGrant = async (roleType: any, addr: any) => {
    try {
      const role = roleType === "supplier"
        ? ethers.keccak256(ethers.toUtf8Bytes("SUPPLIER_ROLE"))
        : ethers.keccak256(ethers.toUtf8Bytes("MANUFACTURER_ROLE"));
      const tx = await contract.grantRole(role, addr);
      await tx.wait();
      alert("Granted!");
    } catch (e: any) {
      alert("Error: " + e.message);
    }
  };

  const handleCreate = async (formData: any) => {
    try {
      const tx = await contract.createShipment(
        parseInt(formData.destLat),
        parseInt(formData.destLong),
        parseInt(formData.radius),
        formData.manufacturer,
        parseInt(formData.rawMaterialId),
        parseInt(formData.amount),
        Math.floor(Date.now() / 1000) + parseInt(formData.eta) * 3600
      );
      await tx.wait();
      setShowCreateModal(false);
      fetchData(contract, escrowContract);
    } catch (e: any) {
      alert("Error: " + e.message);
    }
  };

  const openJoinModal = (role: "supplier" | "manufacturer") => {
    setJoinRole(role);
    setShowJoinModal(true);
  };

  const executeJoin = async () => {
    if (!contract) return;
    let tx;

    // We add { gasLimit: 300000 } as the last argument
    if (joinRole === "supplier") {
      tx = await contract.demoJoinAsSupplier({ gasLimit: 300000 });
    } else {
      tx = await contract.demoJoinAsManufacturer({ gasLimit: 300000 });
    }

    await tx.wait();
  };

  // --- HELPERS ---
  const getStatusColor = (status: any) => {
    switch (status) {
      case "CREATED": return "bg-blue-500";
      case "IN_TRANSIT": return "bg-yellow-500";
      case "ARRIVED": return "bg-green-500";
      default: return "bg-gray-500";
    }
  };

  const getStatusIcon = (status: any) => {
    switch (status) {
      case "CREATED": return <Package className="w-5 h-5" />;
      case "IN_TRANSIT": return <Truck className="w-5 h-5" />;
      case "ARRIVED": return <CheckCircle className="w-5 h-5" />;
      default: return <Clock className="w-5 h-5" />;
    }
  };

  // --- SHIPMENT CREATE MODAL ---
  const CreateShipmentModal = ({ onClose }: { onClose: any }) => {
    const [formData, setFormData] = useState<any>({
      destLat: "", destLong: "", radius: "1000", manufacturer: "",
      rawMaterialId: "1", amount: "", eta: "24",
    });

    return (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
        <div className="bg-white rounded-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
          <div className="p-6 border-b border-gray-200">
            <h2 className="text-2xl font-bold text-gray-900">Create New Shipment</h2>
          </div>
          <div className="p-6 space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Latitude (×10⁶)</label>
                <input type="text" className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-900 bg-white"
                  value={formData.destLat} onChange={(e) => setFormData({ ...formData, destLat: e.target.value })} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Longitude (×10⁶)</label>
                <input type="text" className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-900 bg-white"
                  value={formData.destLong} onChange={(e) => setFormData({ ...formData, destLong: e.target.value })} />
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Manufacturer Address</label>
              <input type="text" className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-900 bg-white"
                value={formData.manufacturer} onChange={(e) => setFormData({ ...formData, manufacturer: e.target.value })} />
            </div>
            <div className="grid grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Material ID</label>
                <select className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-900 bg-white"
                  value={formData.rawMaterialId} onChange={(e) => setFormData({ ...formData, rawMaterialId: e.target.value })}>
                  <option value="1">Steel (1)</option>
                  <option value="2">Copper (2)</option>
                  <option value="3">Aluminum (3)</option>
                  <option value="4">Plastic (4)</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Amount</label>
                <input type="number" className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-900 bg-white"
                  value={formData.amount} onChange={(e) => setFormData({ ...formData, amount: e.target.value })} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">ETA (Hours)</label>
                <input type="number" className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-900 bg-white"
                  value={formData.eta} onChange={(e) => setFormData({ ...formData, eta: e.target.value })} />
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Radius (meters)</label>
              <input type="number" className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-900 bg-white"
                value={formData.radius} onChange={(e) => setFormData({ ...formData, radius: e.target.value })} />
            </div>
          </div>
          <div className="p-6 border-t border-gray-200 flex gap-3">
            <button onClick={onClose} className="flex-1 px-6 py-3 border border-gray-300 text-gray-700 rounded-lg font-medium hover:bg-gray-50">Cancel</button>
            <button onClick={() => handleCreate(formData)} className="flex-1 px-6 py-3 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700">Create Shipment</button>
          </div>
        </div>
      </div>
    );
  };

  // --- 1. LANDING PAGE ---
  if (!walletConnected) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-50 via-white to-purple-50 flex items-center justify-center p-4">
        <div className="max-w-md w-full">
          <div className="bg-white rounded-3xl shadow-xl p-8 text-center space-y-6">
            <div className="w-20 h-20 bg-gradient-to-br from-blue-600 to-purple-600 rounded-2xl mx-auto flex items-center justify-center">
              <Truck className="w-10 h-10 text-white" />
            </div>
            <div>
              <h1 className="text-3xl font-bold text-gray-900 mb-2">RWA Supply Chain</h1>
              <p className="text-gray-600">Real World Assets Tracking Platform</p>
              <p className="text-xs text-gray-500 mt-1">Stagenet</p>
            </div>
            <button onClick={connectWallet} className="w-full bg-gradient-to-r from-blue-600 to-purple-600 text-white py-4 rounded-xl font-semibold hover:shadow-lg transform hover:scale-105 transition-all flex items-center justify-center gap-2">
              <Wallet className="w-5 h-5" /> Connect Wallet
            </button>
          </div>
        </div>
      </div>
    );
  }

  // --- 2. DASHBOARD ---
  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 via-white to-purple-50">
      <header className="bg-white border-b border-gray-200 sticky top-0 z-40 backdrop-blur-lg bg-opacity-90">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-gradient-to-br from-blue-600 to-purple-600 rounded-xl flex items-center justify-center">
                <Truck className="w-6 h-6 text-white" />
              </div>
              <div>
                <h1 className="text-xl font-bold text-gray-900">RWA Supply Chain</h1>
                <p className="text-xs text-gray-500">Blockchain-powered logistics</p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              {/* --- ADMIN ROLE SWITCHER START --- */}
              {userRole === 'admin' && (
                <div className="hidden md:flex items-center gap-2 mr-4 border-r border-gray-300 pr-4">
                  <span className="text-xs font-bold text-gray-500 uppercase tracking-wider">Test View:</span>
                  <button
                    onClick={() => setUserRole('supplier')}
                    className="px-3 py-1.5 rounded-md text-xs font-bold bg-blue-100 text-blue-700 hover:bg-blue-200 transition-colors flex items-center gap-1"
                  >
                    <Database className="w-3 h-3" /> Supplier
                  </button>
                  <button
                    onClick={() => setUserRole('manufacturer')}
                    className="px-3 py-1.5 rounded-md text-xs font-bold bg-green-100 text-green-700 hover:bg-green-200 transition-colors flex items-center gap-1"
                  >
                    <Factory className="w-3 h-3" /> Manufacturer
                  </button>
                  <button
                    onClick={() => setUserRole('admin')}
                    className="px-3 py-1.5 rounded-md text-xs font-bold bg-purple-100 text-purple-700 hover:bg-purple-200 transition-colors"
                  >
                    Reset
                  </button>
                </div>
              )}
              {/* --- ADMIN ROLE SWITCHER END --- */}
              <div className="hidden sm:block px-4 py-2 bg-gray-100 rounded-lg">
                <p className="text-xs text-gray-500">Connected</p>
                <p className="font-mono text-sm font-semibold text-gray-900">{account.slice(0, 6)}...{account.slice(-4)}</p>
              </div>
              <div className={`px-3 py-2 rounded-lg text-sm font-medium capitalize ${userRole === "admin" ? "bg-purple-100 text-purple-700" :
                userRole === "supplier" ? "bg-blue-100 text-blue-700" :
                  userRole === "manufacturer" ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-700"
                }`}>
                {userRole}
              </div>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {userRole === "viewer" ? (
          <div className="max-w-4xl mx-auto px-4 py-12">
            <div className="bg-white rounded-3xl p-8 border border-gray-200 text-center shadow-sm">
              <h2 className="text-2xl font-bold text-gray-900 mb-2">Join the Protocol</h2>
              <p className="text-gray-500 mb-8 max-w-lg mx-auto">To participate in the supply chain, you must apply for a verified role. Please submit your business credentials below.</p>
              <div className="flex flex-col sm:flex-row gap-4 justify-center">
                <button onClick={() => openJoinModal("supplier")} className="flex flex-col items-center p-6 border-2 border-dashed border-gray-300 rounded-xl hover:border-blue-500 hover:bg-blue-50 transition-all w-full sm:w-64">
                  <div className="w-12 h-12 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center mb-3"><Database className="w-6 h-6" /></div>
                  <span className="font-bold text-gray-900">Apply as Supplier</span>
                  <span className="text-xs text-gray-500 mt-1">Mint & Ship Raw Materials</span>
                </button>
                <button onClick={() => openJoinModal("manufacturer")} className="flex flex-col items-center p-6 border-2 border-dashed border-gray-300 rounded-xl hover:border-green-500 hover:bg-green-50 transition-all w-full sm:w-64">
                  <div className="w-12 h-12 bg-green-100 text-green-600 rounded-full flex items-center justify-center mb-3"><Factory className="w-6 h-6" /></div>
                  <span className="font-bold text-gray-900">Apply as Manufacturer</span>
                  <span className="text-xs text-gray-500 mt-1">Receive & Assemble Goods</span>
                </button>
              </div>
            </div>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
              <div className="bg-white rounded-2xl p-6 shadow-sm border border-gray-100">
                <div className="flex items-center justify-between mb-4">
                  <div className="w-12 h-12 bg-blue-100 rounded-xl flex items-center justify-center"><Package className="w-6 h-6 text-blue-600" /></div>
                  <span className="text-2xl font-bold text-gray-900">{shipments.filter((s: any) => s.status === "CREATED").length}</span>
                </div>
                <h3 className="text-gray-600 font-medium">Pending Shipments</h3>
              </div>
              <div className="bg-white rounded-2xl p-6 shadow-sm border border-gray-100">
                <div className="flex items-center justify-between mb-4">
                  <div className="w-12 h-12 bg-yellow-100 rounded-xl flex items-center justify-center"><Truck className="w-6 h-6 text-yellow-600" /></div>
                  <span className="text-2xl font-bold text-gray-900">{shipments.filter((s: any) => s.status === "IN_TRANSIT").length}</span>
                </div>
                <h3 className="text-gray-600 font-medium">In Transit</h3>
              </div>
              <div className="bg-white rounded-2xl p-6 shadow-sm border border-gray-100">
                <div className="flex items-center justify-between mb-4">
                  <div className="w-12 h-12 bg-green-100 rounded-xl flex items-center justify-center"><CheckCircle className="w-6 h-6 text-green-600" /></div>
                  <span className="text-2xl font-bold text-gray-900">{shipments.filter((s: any) => s.status === "ARRIVED").length}</span>
                </div>
                <h3 className="text-gray-600 font-medium">Delivered</h3>
              </div>
            </div>

            <div className="bg-white rounded-2xl shadow-sm border border-gray-100 mb-6">
              <div className="border-b border-gray-200 px-6">
                <div className="flex gap-8 overflow-x-auto">
                  {["shipments", "products", "supplier", "admin"].map((tab) =>
                    (tab === "admin" && userRole !== "admin") ||
                      (tab === "supplier" && userRole !== "supplier") ? null : (
                      <button key={tab} onClick={() => setActiveTab(tab)} className={`py-4 border-b-2 font-medium transition-colors capitalize min-w-max ${activeTab === tab ? "border-blue-600 text-blue-600" : "border-transparent text-gray-500 hover:text-gray-700"
                        }`}>
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
                      <h2 className="text-xl font-bold text-gray-900">Active Shipments</h2>
                      {userRole === "supplier" && (
                        <button onClick={() => setShowCreateModal(true)} className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700 transition-colors">
                          <Plus className="w-4 h-4" /> Create Shipment
                        </button>
                      )}
                    </div>
                    {loading ? (
                      <div className="text-center py-12">
                        <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
                      </div>
                    ) : shipments.length === 0 ? (
                      <div className="text-center py-12">
                        <Package className="w-16 h-16 text-gray-300 mx-auto mb-4" />
                        <p className="text-gray-600">No shipments found</p>
                      </div>
                    ) : (
                      <div className="space-y-4">
                        {shipments.map((shipment: any) => (
                          <div key={shipment.id} className="border border-gray-200 rounded-xl p-6 hover:shadow-md transition-shadow">
                            <div className="flex items-start justify-between mb-4">
                              <div className="flex items-center gap-4">
                                <div className={`w-12 h-12 ${getStatusColor(shipment.status)} rounded-xl flex items-center justify-center text-white`}>
                                  {getStatusIcon(shipment.status)}
                                </div>
                                <div>
                                  <h3 className="font-bold text-gray-900 text-lg">Shipment #{shipment.id}</h3>
                                  <p className="text-gray-600">{shipment.material} • {shipment.amount} units</p>
                                </div>
                              </div>
                              <div className="flex flex-col items-end gap-2">
                                <span className={`px-3 py-1 rounded-full text-xs font-medium ${shipment.status === "ARRIVED" ? "bg-green-100 text-green-700" :
                                  shipment.status === "IN_TRANSIT" ? "bg-yellow-100 text-yellow-700" : "bg-blue-100 text-blue-700"
                                  }`}>
                                  {shipment.status.replace("_", " ")}
                                </span>
                                {shipment.escrow.isFunded && !shipment.escrow.isReleased && (
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
                              <div><p className="text-xs text-gray-500 mb-1">Manufacturer</p><p className="font-mono text-sm font-medium text-gray-900">{shipment.manufacturer ? `${shipment.manufacturer.slice(0, 12)}...` : "Not set"}</p></div>
                              <div><p className="text-xs text-gray-500 mb-1">ETA</p><p className="text-sm font-medium text-gray-900 flex items-center gap-1"><Clock className="w-4 h-4" /> {shipment.eta}</p></div>
                              <div><p className="text-xs text-gray-500 mb-1">Progress</p><p className="text-sm font-medium text-gray-900">{shipment.progress}%</p></div>
                            </div>

                            {shipment.status === "IN_TRANSIT" && (
                              <div className="mb-4">
                                <div className="w-full bg-gray-200 rounded-full h-2">
                                  <div className="bg-blue-600 h-2 rounded-full transition-all" style={{ width: `${shipment.progress}%` }} />
                                </div>
                              </div>
                            )}

                            <div className="flex flex-wrap gap-2">
                              <button className="flex-1 px-4 py-2 border border-gray-300 rounded-lg font-medium text-gray-700 hover:bg-gray-50 flex items-center justify-center gap-2">
                                <MapPin className="w-4 h-4" /> Track
                              </button>

                              {shipment.status === "CREATED" && userRole === "supplier" && (
                                <button onClick={() => handleStartDelivery(shipment.id)} className="flex-1 px-4 py-2 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700 flex items-center justify-center gap-2">
                                  <Send className="w-4 h-4" /> Start Delivery
                                </button>
                              )}

                              {shipment.status === "IN_TRANSIT" && userRole === "manufacturer" && (
                                <button onClick={() => handleForceArrival(shipment.id)} className="flex-1 px-4 py-2 bg-orange-600 text-white rounded-lg font-medium hover:bg-orange-700 flex items-center justify-center gap-2">
                                  <CheckCircle className="w-4 h-4" /> Force Arrival
                                </button>
                              )}

                              {shipment.status === "ARRIVED" && userRole === "manufacturer" && !shipment.consumed && (
                                <button onClick={() => handleAssemble(shipment.id, shipment.amount)} className="flex-1 px-4 py-2 bg-green-600 text-white rounded-lg font-medium hover:bg-green-700 flex items-center justify-center gap-2">
                                  <Factory className="w-4 h-4" /> Assemble
                                </button>
                              )}

                              {shipment.status === "CREATED" && userRole === "manufacturer" && !shipment.escrow.isFunded && (
                                <button onClick={() => handleFundEscrow(shipment.id, shipment.supplier)} className="flex-1 px-4 py-2 bg-purple-600 text-white rounded-lg font-medium hover:bg-purple-700 flex items-center justify-center gap-2">
                                  <Coins className="w-4 h-4" /> Fund Escrow
                                </button>
                              )}
                              {shipment.status === "ARRIVED" && userRole === "manufacturer" && shipment.escrow.isFunded && !shipment.escrow.isReleased && (
                                <button onClick={() => handleReleasePayment(shipment.id)} className="flex-1 px-4 py-2 bg-indigo-600 text-white rounded-lg font-medium hover:bg-indigo-700 flex items-center justify-center gap-2">
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
                {activeTab === "products" && (
                  <>
                    <h2 className="text-xl font-bold text-gray-900 mb-6">Manufactured Products</h2>
                    {products.length === 0 ? (
                      <div className="text-center py-12">
                        <Box className="w-16 h-16 text-gray-300 mx-auto mb-4" />
                        <p className="text-gray-600">No products yet</p>
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                        {products.map((product: any) => (
                          <div key={product.id} className="border border-gray-200 rounded-xl p-6 hover:shadow-md transition-shadow">
                            <div className="flex items-start gap-4 mb-4">
                              <div className="w-12 h-12 bg-purple-100 rounded-xl flex items-center justify-center">
                                <Box className="w-6 h-6 text-purple-600" />
                              </div>
                              <div>
                                <h3 className="font-bold text-gray-900">{product.name}</h3>
                                <p className="text-sm text-gray-600">ID: {product.id}</p>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}
                {activeTab === "supplier" && (
                  <div className="max-w-xl mx-auto space-y-6">
                    <h3 className="text-xl font-bold flex items-center gap-2"><Database /> Mint Raw Materials</h3>
                    <form onSubmit={handleMint} className="space-y-4">
                      <div>
                        <label className="block text-sm font-medium text-gray-700 mb-2">Material</label>
                        <select name="id" className="w-full px-4 py-3 border border-gray-300 rounded-lg text-gray-900 bg-white">
                          <option value="1">Steel</option>
                          <option value="2">Copper</option>
                        </select>
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-700 mb-2">Quantity</label>
                        <input name="amount" type="number" className="w-full px-4 py-3 border border-gray-300 rounded-lg text-gray-900 bg-white" required />
                      </div>
                      <button type="submit" className="w-full bg-green-600 text-white py-3 rounded-lg font-bold hover:bg-green-700">Mint Tokens</button>
                    </form>
                  </div>
                )}
                {activeTab === "admin" && (
                  <div className="max-w-xl mx-auto space-y-6">
                    <h3 className="text-xl font-bold flex items-center gap-2"><Users /> Grant Permissions</h3>
                    <div className="space-y-4">
                      <input id="grantInput" placeholder="Wallet Address (0x...)" className="w-full px-4 py-3 border border-gray-300 rounded-lg text-gray-900 bg-white" />
                      <div className="flex gap-4">
                        <button onClick={() => handleGrant("supplier", (document.getElementById("grantInput") as HTMLInputElement).value)} className="flex-1 bg-slate-900 text-white py-3 rounded-lg font-bold">Grant Supplier</button>
                        <button onClick={() => handleGrant("manufacturer", (document.getElementById("grantInput") as HTMLInputElement).value)} className="flex-1 bg-blue-600 text-white py-3 rounded-lg font-bold">Grant Manufacturer</button>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </>
        )}
      </main>
      {showCreateModal && <CreateShipmentModal onClose={() => setShowCreateModal(false)} />}
      {showJoinModal && <JoinNetworkModal roleType={joinRole} onClose={() => setShowJoinModal(false)} onConfirm={executeJoin} />}
      <footer className="mt-12 border-t border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex flex-col md:flex-row justify-between items-center">
            <div className="flex items-center gap-3 mb-4 md:mb-0">
              <div className="w-8 h-8 bg-gradient-to-br from-blue-600 to-purple-600 rounded-lg flex items-center justify-center"><ShieldCheck className="w-4 h-4 text-white" /></div>
              <div><p className="text-sm font-medium text-gray-900">RWA Supply Chain</p><p className="text-xs text-gray-600">Deployed Contracts Active</p></div>
            </div>
            <div className="text-xs text-gray-500 font-mono">SupplyChain: {CONTRACT_ADDRESS.slice(0, 6)}... | NFT: {PRODUCT_NFT_ADDRESS.slice(0, 6)}...</div>
          </div>
        </div>
      </footer>
    </div>
  );
};

export default SupplyChainDashboard;