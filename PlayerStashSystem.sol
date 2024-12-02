// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

import { System } from "@latticexyz/world/src/System.sol";

import { LibAccount } from "../../libraries/LibAccount.sol";
import { LibAccountLinking } from "../../libraries/LibAccountLinking.sol";
import { LibAmulet } from "../../libraries/LibAmulet.sol";
import { LibBelt } from "../../libraries/LibBelt.sol";
import { LibCharacterState, WORLD_STATE_OPEN_WORLD } from "../../libraries/LibCharacterState.sol";
import { LibInventory } from "../../libraries/LibInventory.sol";
import { LibOnyx } from "../../libraries/LibOnyx.sol";
import { LibRunix } from "../../libraries/LibRunix.sol";
import { LibShip } from "../../libraries/LibShip.sol";

import { IAmuletTokenSystem } from "../../codegen/world/IAmuletTokenSystem.sol";
import { IItemTokenSystem } from "../../codegen/world/IItemTokenSystem.sol";
import { IOnyxTokenSystem } from "../../codegen/world/IOnyxTokenSystem.sol";
import { IRunixTokenSystem } from "../../codegen/world/IRunixTokenSystem.sol";
import { IShipTokenSystem } from "../../codegen/world/IShipTokenSystem.sol";

/**
 * @title PlayerStashSystem
 * @dev Provides functions for managing the exchange of items, ships, amulets, and currencies within a player's stash.
 */
contract PlayerStashSystem is System {
  /**
   * @dev Error indicating that the character's belt is empty.
   * @param characterId The unique identifier of the character with an empty belt.
   */
  error PlayerStash_BeltEmpty(uint64 characterId);

  /**
   * @dev Error indicating that the character's belt is overflowing.
   * @param characterId The unique identifier of the character with an overflowing belt.
   */
  error PlayerStash_BeltOverflow(uint64 characterId);

  /**
   * @dev Error indicating that a ship change is not allowed.
   */
  error PlayerStash_NoShipChange();

  /**
   * @dev Error indicating that the ship is already set for the character.
   * @param characterId The unique identifier of the character.
   * @param shipId The unique identifier of the ship that is already set.
   */
  error PlayerStash_ShipAlreadySet(uint64 characterId, uint64 shipId);

  /**
   * @dev Error indicating that the amulet is soulbound and thus not transferrable.
   * @param amuletId The unique identifier of the character.
   */
  error PlayerStash_SoulboundAmulet(uint64 amuletId);

  /**
   * @dev Error indicating that too many ships are being exchanged.
   * @param depositLength The number of ships being deposited.
   * @param withdrawalLength The number of ships being withdrawn.
   */
  error PlayerStash_TooManyShips(uint256 depositLength, uint256 withdrawalLength);

  /**
   * @notice Exchanges amulets between the player's stash and the character's inventory.
   * @param depositAmuletIds An array of uint64 values representing the IDs of amulets to deposit.
   * @param withdrawalAmuletIds An array of uint64 values representing the IDs of amulets to withdraw.
   */
  function exchangeAmulets(uint64[] memory depositAmuletIds, uint64[] memory withdrawalAmuletIds) public {
    address mainAccount = LibAccountLinking.getAndValidateActiveAccount(_msgSender());
    uint64 characterId = LibAccount.getSelectedCharacterId(mainAccount);

    LibCharacterState.validateState(characterId, WORLD_STATE_OPEN_WORLD);

    for (uint256 i = 0; i < withdrawalAmuletIds.length; i++) {
      if (LibAmulet.isSoulbound(withdrawalAmuletIds[i])) {
        revert PlayerStash_SoulboundAmulet(withdrawalAmuletIds[i]);
      }
      LibAmulet.validateOwner(withdrawalAmuletIds[i], characterId);
      IAmuletTokenSystem(_world()).valhalla__withdrawAmulet(mainAccount, withdrawalAmuletIds[i]);
      LibAmulet.validateEmpty(withdrawalAmuletIds[i]);
      LibInventory.removeAmulet(characterId, withdrawalAmuletIds[i], false);
    }

    for (uint256 i = 0; i < depositAmuletIds.length; i++) {
      IAmuletTokenSystem(_world()).valhalla__depositAmulet(mainAccount, depositAmuletIds[i]);
      LibAmulet.setOwner(depositAmuletIds[i], characterId);
      LibAmulet.validateEmpty(depositAmuletIds[i]);
      LibInventory.addAmulet(characterId, depositAmuletIds[i]);
    }
  }

  /**
   * @notice Exchanges currencies (Runix and Onyx) between the player's stash and the character's inventory.
   * @param depositRunix A uint64 value representing the amount of Runix to deposit.
   * @param withdrawalRunix A uint64 value representing the amount of Runix to withdraw.
   * @param depositOnyx A uint64 value representing the amount of Onyx to deposit.
   * @param withdrawalOnyx A uint64 value representing the amount of Onyx to withdraw.
   */
  function exchangeCurrencies(
    uint64 depositRunix,
    uint64 withdrawalRunix,
    uint64 depositOnyx,
    uint64 withdrawalOnyx
  ) public {
    address mainAccount = LibAccountLinking.getAndValidateActiveAccount(_msgSender());
    uint64 characterId = LibAccount.getSelectedCharacterId(mainAccount);

    LibCharacterState.validateState(characterId, WORLD_STATE_OPEN_WORLD);

    if (depositRunix > 0) {
      IRunixTokenSystem(_world()).valhalla__depositRunix(mainAccount, depositRunix);
      LibRunix.addRunix(characterId, depositRunix);
    }

    if (depositOnyx > 0) {
      IOnyxTokenSystem(_world()).valhalla__depositOnyx(mainAccount, depositOnyx);
      LibOnyx.addOnyx(characterId, depositOnyx);
    }

    if (withdrawalRunix > 0) {
      IRunixTokenSystem(_world()).valhalla__withdrawRunix(mainAccount, withdrawalRunix);
      LibRunix.deductRunix(characterId, withdrawalRunix);
    }

    if (withdrawalOnyx > 0) {
      IOnyxTokenSystem(_world()).valhalla__withdrawOnyx(mainAccount, withdrawalOnyx);
      LibOnyx.deductOnyx(characterId, withdrawalOnyx);
    }
  }

  /**
   * @notice Exchanges filled amulets between the player's stash and the character's belt.
   * @dev Filled amulet have their `veraId` attribute set to a non-zero value, i.e. they contain a Vera.
   * @param depositAmuletIds An array of uint64 values representing the IDs of filled amulets to deposit.
   * @param withdrawalAmuletIds An array of uint64 values representing the IDs of filled amulets to withdraw.
   */
  function exchangeFilledAmulets(uint64[] memory depositAmuletIds, uint64[] memory withdrawalAmuletIds) public {
    address mainAccount = LibAccountLinking.getAndValidateActiveAccount(_msgSender());
    uint64 characterId = LibAccount.getSelectedCharacterId(mainAccount);

    LibCharacterState.validateState(characterId, WORLD_STATE_OPEN_WORLD);

    for (uint256 i = 0; i < withdrawalAmuletIds.length; i++) {
      if (LibAmulet.isSoulbound(withdrawalAmuletIds[i])) {
        revert PlayerStash_SoulboundAmulet(withdrawalAmuletIds[i]);
      }

      LibAmulet.validateOwner(withdrawalAmuletIds[i], characterId);
      IAmuletTokenSystem(_world()).valhalla__withdrawAmulet(mainAccount, withdrawalAmuletIds[i]);
      LibAmulet.validateFilled(withdrawalAmuletIds[i]);
      LibBelt.removeAmulet(characterId, withdrawalAmuletIds[i]);
    }

    for (uint256 i = 0; i < depositAmuletIds.length; i++) {
      IAmuletTokenSystem(_world()).valhalla__depositAmulet(mainAccount, depositAmuletIds[i]);
      LibAmulet.setOwner(depositAmuletIds[i], characterId);
      LibAmulet.validateFilled(depositAmuletIds[i]);
      LibBelt.addAmulet(characterId, depositAmuletIds[i]);
    }

    if (LibBelt.isOverflowing(characterId)) {
      revert PlayerStash_BeltOverflow(characterId);
    }

    uint64[] memory beltAmuletIds = LibBelt.getAmuletIds(characterId);
    if (beltAmuletIds.length == 0) {
      revert PlayerStash_BeltEmpty(characterId);
    }
  }

  /**
   * @notice Exchanges items between the player's stash and the character's inventory.
   * @param depositItemIds An array of uint64 values representing the IDs of items to deposit.
   * @param depositItemQuantities An array of uint64 values representing the quantities of each item to deposit.
   * @param withdrawalItemIds An array of uint64 values representing the IDs of items to withdraw.
   * @param withdrawalItemQuantities An array of uint64 values representing the quantities of each item to withdraw.
   */
  function exchangeItems(
    uint64[] memory depositItemIds,
    uint64[] memory depositItemQuantities,
    uint64[] memory withdrawalItemIds,
    uint64[] memory withdrawalItemQuantities
  ) public {
    address mainAccount = LibAccountLinking.getAndValidateActiveAccount(_msgSender());
    uint64 characterId = LibAccount.getSelectedCharacterId(mainAccount);

    LibCharacterState.validateState(characterId, WORLD_STATE_OPEN_WORLD);

    for (uint256 i = 0; i < withdrawalItemIds.length; i++) {
      IItemTokenSystem(_world()).valhalla__withdrawItem(mainAccount, withdrawalItemIds[i], withdrawalItemQuantities[i]);
      LibInventory.deductItem(characterId, withdrawalItemIds[i], withdrawalItemQuantities[i]);
    }

    for (uint256 i = 0; i < depositItemIds.length; i++) {
      IItemTokenSystem(_world()).valhalla__depositItem(mainAccount, depositItemIds[i], depositItemQuantities[i]);
      LibInventory.addItem(characterId, depositItemIds[i], depositItemQuantities[i]);
    }
  }

  /**
   * @notice Exchanges ships between the player's stash and the character's inventory.
   * @param depositShipIds An array of uint64 values representing the IDs of ships to deposit.
   * @param withdrawalShipIds An array of uint64 values representing the IDs of ships to withdraw.
   */
  function exchangeShips(uint64[] memory depositShipIds, uint64[] memory withdrawalShipIds) public {
    address mainAccount = LibAccountLinking.getAndValidateActiveAccount(_msgSender());
    uint64 characterId = LibAccount.getSelectedCharacterId(mainAccount);

    LibCharacterState.validateState(characterId, WORLD_STATE_OPEN_WORLD);

    if (depositShipIds.length > 1) {
      revert PlayerStash_TooManyShips(depositShipIds.length, withdrawalShipIds.length);
    }

    if (withdrawalShipIds.length > 1) {
      revert PlayerStash_TooManyShips(depositShipIds.length, withdrawalShipIds.length);
    }

    if (withdrawalShipIds.length == 1) {
      LibShip.validateOwner(withdrawalShipIds[0], characterId);
      LibShip.clear(characterId);

      IShipTokenSystem(_world()).valhalla__withdrawShip(mainAccount, withdrawalShipIds[0]);
    }

    if (depositShipIds.length == 1) {
      IShipTokenSystem(_world()).valhalla__depositShip(mainAccount, depositShipIds[0]);
      LibShip.set(characterId, depositShipIds[0]);
    }
  }
}
