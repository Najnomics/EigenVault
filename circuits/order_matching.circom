pragma circom 2.0.0;

/*
 * Order Matching Circuit for EigenVault
 * 
 * This circuit proves that order matching was performed correctly
 * without revealing the actual order details (price, amount, trader)
 * 
 * Public inputs:
 * - Order commitments (hashes of order data)
 * - Match result hash
 * - Pool key
 * 
 * Private inputs:
 * - Order details (price, amount, trader, etc.)
 * - Matching algorithm parameters
 */

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";

template OrderMatching(nOrders) {
    // Public inputs
    signal input orderCommitments[nOrders];
    signal input matchResultHash;
    signal input poolKey;
    
    // Private inputs - order details
    signal private input orderPrices[nOrders];
    signal private input orderAmounts[nOrders];
    signal private input orderTypes[nOrders]; // 0 = buy, 1 = sell
    signal private input traderHashes[nOrders];
    signal private input orderNonces[nOrders];
    
    // Private inputs - matching parameters
    signal private input matchedPrice;
    signal private input matchedAmount;
    signal private input buyOrderIndex;
    signal private input sellOrderIndex;
    
    // Outputs
    signal output isValidMatch;
    
    // Component declarations
    component poseidonHashers[nOrders];
    component priceComparator = GreaterEqThan(64);
    component amountComparator = LessEqThan(64);
    component typeChecker1 = IsEqual();
    component typeChecker2 = IsEqual();
    component matchHasher = Poseidon(4);
    component matchValidator = IsEqual();
    
    // Verify order commitments
    for (var i = 0; i < nOrders; i++) {
        poseidonHashers[i] = Poseidon(5);
        poseidonHashers[i].inputs[0] <== orderPrices[i];
        poseidonHashers[i].inputs[1] <== orderAmounts[i];
        poseidonHashers[i].inputs[2] <== orderTypes[i];
        poseidonHashers[i].inputs[3] <== traderHashes[i];
        poseidonHashers[i].inputs[4] <== orderNonces[i];
        
        // Verify commitment matches the provided hash
        poseidonHashers[i].out === orderCommitments[i];
    }
    
    // Verify matching logic
    // 1. Buy order type should be 0, sell order type should be 1
    typeChecker1.in[0] <== orderTypes[buyOrderIndex];
    typeChecker1.in[1] <== 0;
    typeChecker1.out === 1;
    
    typeChecker2.in[0] <== orderTypes[sellOrderIndex];
    typeChecker2.in[1] <== 1;
    typeChecker2.out === 1;
    
    // 2. Buy price should be >= sell price (orders can match)
    priceComparator.in[0] <== orderPrices[buyOrderIndex];
    priceComparator.in[1] <== orderPrices[sellOrderIndex];
    priceComparator.out === 1;
    
    // 3. Matched amount should not exceed either order's amount
    amountComparator.in[0] <== matchedAmount;
    amountComparator.in[1] <== orderAmounts[buyOrderIndex];
    amountComparator.out === 1;
    
    amountComparator.in[0] <== matchedAmount;
    amountComparator.in[1] <== orderAmounts[sellOrderIndex];
    amountComparator.out === 1;
    
    // 4. Matched price should be between buy and sell prices
    priceComparator.in[0] <== matchedPrice;
    priceComparator.in[1] <== orderPrices[sellOrderIndex];
    priceComparator.out === 1;
    
    priceComparator.in[0] <== orderPrices[buyOrderIndex];
    priceComparator.in[1] <== matchedPrice;
    priceComparator.out === 1;
    
    // Verify match result hash
    matchHasher.inputs[0] <== matchedPrice;
    matchHasher.inputs[1] <== matchedAmount;
    matchHasher.inputs[2] <== buyOrderIndex;
    matchHasher.inputs[3] <== sellOrderIndex;
    
    matchValidator.in[0] <== matchHasher.out;
    matchValidator.in[1] <== matchResultHash;
    
    // Output the validation result
    isValidMatch <== matchValidator.out;
}

// Main component for 10 orders maximum
component main = OrderMatching(10);