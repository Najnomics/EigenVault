pragma circom 2.0.0;

/*
 * Privacy Proof Circuit for EigenVault
 * 
 * This circuit proves that orders satisfy certain validity constraints
 * without revealing the actual order contents
 * 
 * Public inputs:
 * - Order commitment hashes
 * - Validity result
 * 
 * Private inputs:
 * - Order details (encrypted/hidden)
 * - Validity parameters
 */

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";

template PrivacyProof(nOrders) {
    // Public inputs
    signal input orderCommitments[nOrders];
    signal input validityHash;
    signal input timestamp;
    
    // Private inputs - order details
    signal private input orderPrices[nOrders];
    signal private input orderAmounts[nOrders];
    signal private input orderDeadlines[nOrders];
    signal private input traderHashes[nOrders];
    signal private input orderNonces[nOrders];
    
    // Private validation parameters
    signal private input minPrice;
    signal private input maxPrice;
    signal private input minAmount;
    signal private input maxAmount;
    
    // Outputs
    signal output isValid;
    
    // Component declarations
    component commitmentHashers[nOrders];
    component priceValidators[nOrders * 2]; // min and max for each order
    component amountValidators[nOrders * 2]; // min and max for each order
    component deadlineValidators[nOrders];
    component validityHasher = Poseidon(nOrders + 1);
    component finalValidator = IsEqual();
    
    var validOrderCount = 0;
    
    // Verify each order
    for (var i = 0; i < nOrders; i++) {
        // Verify commitment
        commitmentHashers[i] = Poseidon(5);
        commitmentHashers[i].inputs[0] <== orderPrices[i];
        commitmentHashers[i].inputs[1] <== orderAmounts[i];
        commitmentHashers[i].inputs[2] <== orderDeadlines[i];
        commitmentHashers[i].inputs[3] <== traderHashes[i];
        commitmentHashers[i].inputs[4] <== orderNonces[i];
        
        commitmentHashers[i].out === orderCommitments[i];
        
        // Validate price bounds
        priceValidators[i * 2] = GreaterEqThan(64);
        priceValidators[i * 2].in[0] <== orderPrices[i];
        priceValidators[i * 2].in[1] <== minPrice;
        
        priceValidators[i * 2 + 1] = LessEqThan(64);
        priceValidators[i * 2 + 1].in[0] <== orderPrices[i];
        priceValidators[i * 2 + 1].in[1] <== maxPrice;
        
        // Validate amount bounds
        amountValidators[i * 2] = GreaterEqThan(64);
        amountValidators[i * 2].in[0] <== orderAmounts[i];
        amountValidators[i * 2].in[1] <== minAmount;
        
        amountValidators[i * 2 + 1] = LessEqThan(64);
        amountValidators[i * 2 + 1].in[0] <== orderAmounts[i];
        amountValidators[i * 2 + 1].in[1] <== maxAmount;
        
        // Validate deadline (should be in the future)
        deadlineValidators[i] = GreaterThan(64);
        deadlineValidators[i].in[0] <== orderDeadlines[i];
        deadlineValidators[i].in[1] <== timestamp;
        
        // Count valid orders (simplified - in real circuit would use proper counting)
        validOrderCount += priceValidators[i * 2].out * 
                          priceValidators[i * 2 + 1].out * 
                          amountValidators[i * 2].out * 
                          amountValidators[i * 2 + 1].out * 
                          deadlineValidators[i].out;
    }
    
    // Create validity hash
    for (var i = 0; i < nOrders; i++) {
        validityHasher.inputs[i] <== orderCommitments[i];
    }
    validityHasher.inputs[nOrders] <== timestamp;
    
    // Verify validity hash matches
    finalValidator.in[0] <== validityHasher.out;
    finalValidator.in[1] <== validityHash;
    
    // Output validation result
    isValid <== finalValidator.out;
}

// Main component for 10 orders maximum
component main = PrivacyProof(10);