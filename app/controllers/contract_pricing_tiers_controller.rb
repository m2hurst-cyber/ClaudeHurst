class ContractPricingTiersController < ApplicationController
  def destroy
    tier = ContractPricingTier.find(params[:id])
    contract = tier.contract
    tier.destroy
    redirect_to contract, notice: "Pricing tier removed."
  end
end
